import 'package:flutter/material.dart';

import '../domain/schedule.dart';
import '../domain/task.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec'
];

String dateLabel(String ymd) {
  final d = DateTime.parse(ymd);
  return '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
}

/// "10:00", "10:00–11:00", or "10:00 → Sat 17 Oct 11:00" when the end is on another day.
String? timeLabel(Task t) {
  final start = t.startTime;
  final end = t.endTime;
  final endDay = t.endDate != null && t.endDate != t.startDate
      ? dateLabel(t.endDate!)
      : null;
  if (start == null) return endDay == null ? null : '→ $endDay${end == null ? '' : ' $end'}';
  if (endDay != null) return '$start → $endDay${end == null ? '' : ' $end'}';
  return end == null ? start : '$start–$end';
}

/// One task. No card: just the check circle, the name, quiet metadata, and a rounded hover/press area.
class TaskRow extends StatelessWidget {
  const TaskRow(
      {super.key,
      required this.task,
      required this.now,
      this.showDate = false,
      this.onTap,
      this.onToggle});

  final Task task;
  final DateTime now;
  final bool showDate;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final meta = [
      if (showDate && task.startDate != null) dateLabel(task.startDate!),
      if (timeLabel(task) != null) timeLabel(task)!,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.only(left: 4, right: 12, bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(
              label: task.done
                  ? 'Mark "${task.name}" not done'
                  : 'Mark "${task.name}" done',
              child: Checkbox(
                  value: task.done,
                  onChanged:
                      onToggle == null ? null : (v) => onToggle!(v ?? false)),
            ),
            const SizedBox(width: 2),
            Expanded(
              // Done is shown with a strikethrough and the muted color (6.9:1), not by fading: opacity would push the
              // text under 4.5:1 and a finished task is still something you may want to read.
              child: Padding(
                // centers the first line on the 48dp check circle
                padding: const EdgeInsets.only(top: 11),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                          decoration:
                              task.done ? TextDecoration.lineThrough : null,
                          decorationColor: scheme.onSurfaceVariant,
                          color: task.done ? scheme.onSurfaceVariant : null,
                        ),
                      ),
                      if (meta.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(meta,
                              style: text.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                        ),
                      if (task.people.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Wrap(spacing: 6, runSpacing: 4, children: [
                            for (final p in task.people)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 9, vertical: 3),
                                decoration: BoxDecoration(
                                    color: scheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(99)),
                                child: Text(p,
                                    style: text.labelSmall?.copyWith(
                                        color: scheme.onSecondaryContainer)),
                              ),
                          ]),
                        ),
                    ]),
              ),
            ),
            if (task.reminder)
              Padding(
                padding: const EdgeInsets.only(top: 15, left: 10),
                child: Icon(Icons.notifications_none_rounded,
                    size: 18,
                    semanticLabel: 'Reminder on',
                    color: scheme.onSurfaceVariant),
              ),
            if (isDue(task, now))
              Padding(
                padding: const EdgeInsets.only(top: 13, left: 8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(99)),
                  child: Text('Due',
                      style: text.labelSmall
                          ?.copyWith(color: scheme.onPrimaryContainer)),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
