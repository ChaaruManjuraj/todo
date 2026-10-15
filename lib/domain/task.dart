const _unset = Object();

/// Wall-clock task. Dates are `YYYY-MM-DD`, times `HH:mm`, no timezone.
class Task {
  const Task({
    required this.id,
    required this.name,
    this.startDate,
    this.startTime,
    this.endDate,
    this.endTime,
    this.people = const [],
    this.notes = '',
    this.reminder = false,
    this.done = false,
    this.doneAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String? startDate, startTime, endDate, endTime;
  final List<String> people;
  final String notes;
  final bool reminder, done;
  final DateTime? doneAt;
  final DateTime createdAt, updatedAt;

  /// Nullable fields use a sentinel so `copyWith(startDate: null)` clears them.
  Task copyWith({
    String? name,
    Object? startDate = _unset,
    Object? startTime = _unset,
    Object? endDate = _unset,
    Object? endTime = _unset,
    List<String>? people,
    String? notes,
    bool? reminder,
    bool? done,
    Object? doneAt = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      Task(
        id: id,
        name: name ?? this.name,
        startDate: identical(startDate, _unset) ? this.startDate : startDate as String?,
        startTime: identical(startTime, _unset) ? this.startTime : startTime as String?,
        endDate: identical(endDate, _unset) ? this.endDate : endDate as String?,
        endTime: identical(endTime, _unset) ? this.endTime : endTime as String?,
        people: people ?? this.people,
        notes: notes ?? this.notes,
        reminder: reminder ?? this.reminder,
        done: done ?? this.done,
        doneAt: identical(doneAt, _unset) ? this.doneAt : doneAt as DateTime?,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// Timestamps are ISO-8601 strings; the Firestore layer maps them to native timestamps.
  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'startDate': startDate,
        'startTime': startTime,
        'endDate': endDate,
        'endTime': endTime,
        'people': people,
        'notes': notes,
        'reminder': reminder,
        'done': done,
        'doneAt': doneAt?.toUtc().toIso8601String(),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory Task.fromJson(Map<String, Object?> j) => Task(
        id: j['id'] as String,
        name: j['name'] as String,
        startDate: j['startDate'] as String?,
        startTime: j['startTime'] as String?,
        endDate: j['endDate'] as String?,
        endTime: j['endTime'] as String?,
        people: [for (final p in (j['people'] as List? ?? const [])) p as String],
        notes: j['notes'] as String? ?? '',
        reminder: j['reminder'] as bool? ?? false,
        done: j['done'] as bool? ?? false,
        doneAt: _ts(j['doneAt']),
        createdAt: _ts(j['createdAt'])!,
        updatedAt: _ts(j['updatedAt'])!,
      );

  @override
  bool operator ==(Object other) => other is Task && _eq(toJson(), other.toJson());
  @override
  int get hashCode => id.hashCode;
}

DateTime? _ts(Object? v) => v == null ? null : DateTime.parse(v as String).toUtc();

bool _eq(Map<String, Object?> a, Map<String, Object?> b) {
  for (final k in a.keys) {
    final x = a[k], y = b[k];
    if (x is List ? !(y is List && x.length == y.length && Iterable.generate(x.length).every((i) => x[i] == y[i])) : x != y) {
      return false;
    }
  }
  return true;
}
