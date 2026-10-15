import 'dart:convert';

import 'task.dart';

enum Section { past, today, tomorrow, later, noDate, completed }

final _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _time = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

String fmtDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// First problem with [t], or null when valid.
String? validate(Task t) {
  if (t.name.trim().isEmpty) return 'Name is required';
  if (t.name.length > 200) return 'Name must be 200 characters or fewer';
  if (t.notes.length > 5000) return 'Notes must be 5,000 characters or fewer';
  for (final d in [t.startDate, t.endDate]) {
    if (d != null && !_date.hasMatch(d)) return 'Invalid date';
  }
  for (final s in [t.startTime, t.endTime]) {
    if (s != null && !_time.hasMatch(s)) return 'Invalid time';
  }
  if (t.startDate == null) {
    if (t.startTime != null) return 'A time needs a start date';
    if (t.endDate != null || t.endTime != null) return 'An end needs a start date';
    if (t.reminder) return 'A reminder needs a start date';
    return null;
  }
  final endDate = t.endDate ?? t.startDate!;
  if (endDate.compareTo(t.startDate!) < 0) return 'End must be after start';
  if (endDate == t.startDate && t.startTime != null && t.endTime != null && t.endTime!.compareTo(t.startTime!) <= 0) {
    return 'End must be after start';
  }
  return null;
}

/// Clearing the start date drops everything that depends on it (§5).
Task clearStart(Task t) =>
    t.copyWith(startDate: null, startTime: null, endDate: null, endTime: null, reminder: false);

String sortKey(Task t) => '${t.startDate ?? ''}${t.startTime ?? ''}';

/// Start date + time, or 09:00 on the start date when there is no time.
DateTime? startInstant(Task t) {
  final d = t.startDate;
  if (d == null) return null;
  final p = d.split('-').map(int.parse).toList();
  final tm = (t.startTime ?? '09:00').split(':').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2], tm[0], tm[1]);
}

bool isDue(Task t, DateTime now) {
  final at = startInstant(t);
  return t.reminder && !t.done && at != null && !at.isAfter(now);
}

/// Start instant and next-day 09:00, minus anything already past. Empty for done tasks.
List<({int id, DateTime at})> reminderInstants(Task t, DateTime now) {
  final start = startInstant(t);
  if (!t.reminder || t.done || start == null) return const [];
  final next = DateTime(start.year, start.month, start.day + 1, 9);
  return [
    for (final (slot, at) in [(0, start), (1, next)])
      if (at.isAfter(now)) (id: notificationId(t.id, slot), at: at),
  ];
}

/// 32-bit FNV-1a. Pinned by a test: changing it orphans scheduled notifications.
int fnv1a(String s) {
  var h = 0x811c9dc5;
  for (final b in utf8.encode(s)) {
    h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF; // ponytail: exact on VM; Android-only caller, split the multiply if web ever needs it
  }
  return h;
}

int notificationId(String taskId, int slot) => (fnv1a(taskId) * 2 + slot) & 0x7FFFFFFF;

Map<Section, List<Task>> groupTasks(List<Task> tasks, DateTime now, {bool showAllCompleted = false}) {
  final today = fmtDate(now);
  final tomorrow = fmtDate(DateTime(now.year, now.month, now.day + 1));
  final cutoff = now.subtract(const Duration(hours: 24));
  final out = <Section, List<Task>>{};
  for (final t in tasks) {
    final Section s;
    if (t.done) {
      if (!showAllCompleted && t.doneAt != null && t.doneAt!.isBefore(cutoff)) continue;
      s = Section.completed;
    } else if (t.startDate == null) {
      s = Section.noDate;
    } else if (t.startDate!.compareTo(today) < 0) {
      s = Section.past;
    } else if (t.startDate == today) {
      s = Section.today;
    } else if (t.startDate == tomorrow) {
      s = Section.tomorrow;
    } else {
      s = Section.later;
    }
    (out[s] ??= []).add(t);
  }
  for (final e in out.entries) {
    e.value.sort(e.key == Section.completed
        ? (a, b) => (b.doneAt ?? b.updatedAt).compareTo(a.doneAt ?? a.updatedAt)
        : (a, b) {
            final c = sortKey(a).compareTo(sortKey(b));
            return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
          });
  }
  return {for (final s in Section.values) if (out[s] != null) s: out[s]!};
}

/// Distinct names across tasks, most used first (ties alphabetical).
List<String> knownPeople(List<Task> tasks) {
  final n = <String, int>{};
  for (final t in tasks) {
    for (final p in t.people) {
      n[p] = (n[p] ?? 0) + 1;
    }
  }
  return n.keys.toList()..sort((a, b) => n[b]! != n[a]! ? n[b]! - n[a]! : a.compareTo(b));
}
