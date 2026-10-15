import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/schedule.dart';
import '../domain/task.dart';
import '../reminders/reminder_scheduler.dart';
import 'people_field.dart';
import 'task_row.dart';

/// True while a text field has keyboard focus, so single-key shortcuts must not fire.
bool focusInTextField() => FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() != null;

class _Close extends Intent {
  const _Close();
}

class _Save extends Intent {
  const _Save();
}

class _Guarded<T extends Intent> extends Action<T> {
  _Guarded(this.enabled, this.run);
  final bool Function() enabled;
  final VoidCallback run;
  @override
  bool isEnabled(T intent) => enabled();
  @override
  Object? invoke(T intent) {
    run();
    return null;
  }
}

String _hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class TaskDetail extends StatefulWidget {
  const TaskDetail({
    super.key,
    required this.task,
    required this.knownPeople,
    required this.now,
    required this.onSave,
    required this.onDelete,
    required this.onClose,
  });

  final Task task;
  final List<String> knownPeople;
  final DateTime now;
  final ValueChanged<Task> onSave;
  final VoidCallback onDelete, onClose;

  @override
  State<TaskDetail> createState() => _TaskDetailState();
}

class _TaskDetailState extends State<TaskDetail> {
  late final _name = TextEditingController(text: widget.task.name);
  late final _notes = TextEditingController(text: widget.task.notes);
  final _nameFocus = FocusNode();
  final _notesFocus = FocusNode();
  late Task _draft = widget.task;
  bool _notificationsBlocked = false;

  @override
  void initState() {
    super.initState();
    // `autofocus` is ignored when the surrounding scope already has a focused child (the wide side panel).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nameFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    _nameFocus.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  Task get _current => _draft.copyWith(name: _name.text.trim(), notes: _notes.text);

  void _update(Task t) => setState(() => _draft = t);

  /// Turning a reminder on asks for notification permission (Android; first time only shows a prompt). It stays on
  /// if denied, but a warning explains it won't fire.
  Future<void> _setReminder(bool on) async {
    _update(_current.copyWith(reminder: on));
    final ask = requestNotificationPermission;
    if (!on || ask == null) return;
    final granted = await ask();
    if (mounted) setState(() => _notificationsBlocked = !granted);
  }

  Future<void> _pickDate({required bool end}) async {
    final existing = end ? _draft.endDate : _draft.startDate;
    final base = existing != null ? DateTime.parse(existing) : (_draft.startDate != null ? DateTime.parse(_draft.startDate!) : widget.now);
    final d = await showDatePicker(context: context, initialDate: base, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d == null) return;
    final s = fmtDate(d);
    _update(end ? _current.copyWith(endDate: s) : _current.copyWith(startDate: s));
  }

  Future<void> _pickTime({required bool end}) async {
    final existing = end ? _draft.endTime : _draft.startTime;
    final p = existing?.split(':').map(int.parse).toList();
    final t = await showTimePicker(
      context: context,
      initialTime: p != null ? TimeOfDay(hour: p[0], minute: p[1]) : const TimeOfDay(hour: 9, minute: 0),
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t == null) return;
    _update(end ? _current.copyWith(endTime: _hhmm(t)) : _current.copyWith(startTime: _hhmm(t)));
  }

  Widget _pick(String label, String? value, VoidCallback? onTap, VoidCallback? onClear) => Expanded(
        child: Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: onTap,
              child: Align(alignment: Alignment.centerLeft, child: Text(value ?? label, overflow: TextOverflow.ellipsis)),
            ),
          ),
          if (value != null) IconButton(tooltip: 'Clear $label', icon: const Icon(Icons.close, size: 18), onPressed: onClear),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final cur = _current;
    final error = validate(cur);
    final hasStart = cur.startDate != null;

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): _Close(),
        SingleActivator(LogicalKeyboardKey.enter): _Save(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): _Save(),
      },
      child: Actions(
        actions: {
          _Close: _Guarded<_Close>(() => true, widget.onClose),
          // Enter in notes inserts a newline and in People adds a chip, so it only saves elsewhere.
          _Save: _Guarded<_Save>(() => !_notesFocus.hasFocus && !PeopleField.hasFocus() && error == null, () => widget.onSave(_current)),
        },
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), shrinkWrap: true, children: [
            Row(children: [
              Expanded(child: Text('Task', style: Theme.of(context).textTheme.titleMedium)),
              IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: widget.onClose),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              focusNode: _nameFocus,
              maxLength: 200,
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Row(children: [
              _pick('Start date', cur.startDate == null ? null : dateLabel(cur.startDate!), () => _pickDate(end: false),
                  () => _update(clearStart(_current))),
              const SizedBox(width: 8),
              _pick('Start time', cur.startTime, hasStart ? () => _pickTime(end: false) : null,
                  () => _update(_current.copyWith(startTime: null))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              _pick('End date', cur.endDate == null ? null : dateLabel(cur.endDate!), hasStart ? () => _pickDate(end: true) : null,
                  () => _update(_current.copyWith(endDate: null))),
              const SizedBox(width: 8),
              _pick('End time', cur.endTime, hasStart ? () => _pickTime(end: true) : null,
                  () => _update(_current.copyWith(endTime: null))),
            ]),
            const SizedBox(height: 12),
            PeopleField(
              selected: cur.people,
              suggestions: widget.knownPeople,
              onChanged: (p) => _update(_current.copyWith(people: p)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              focusNode: _notesFocus,
              minLines: 3,
              maxLines: 6,
              maxLength: 5000,
              // a counter on an empty field is noise: only show it when the limit is near
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                  currentLength < 4500 ? null : Text('$currentLength/$maxLength'),
              decoration: const InputDecoration(labelText: 'Notes'),
              onChanged: (_) => setState(() {}),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Reminder'),
              subtitle: hasStart ? null : const Text('Set a start date first'),
              value: cur.reminder,
              onChanged: hasStart ? _setReminder : null,
            ),
            if (_notificationsBlocked && cur.reminder)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.warning_amber_rounded, size: 18, color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Notifications are blocked for this app, so this reminder won't fire. Allow them in system settings.",
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ]),
              ),
            if (error != null)
              Semantics(
                liveRegion: true,
                child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 8),
            Row(children: [
              TextButton.icon(
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
                style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              ),
              const Spacer(),
              FilledButton(onPressed: error == null ? () => widget.onSave(_current) : null, child: const Text('Save')),
            ]),
          ]),
        ),
      ),
    );
  }
}
