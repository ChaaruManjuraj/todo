import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/task_repository.dart';
import '../domain/schedule.dart';
import '../domain/task.dart';
import '../reminders/reminder_scheduler.dart';
import 'animated_task_list.dart';
import 'clock.dart';
import 'empty_state.dart';
import 'quick_add_bar.dart';
import 'task_detail.dart';
import 'task_row.dart';
import 'theme_controller.dart';

const _titles = {
  Section.past: 'Past',
  Section.today: 'Today',
  Section.tomorrow: 'Tomorrow',
  Section.later: 'Later',
  Section.noDate: 'No date',
  Section.completed: 'Completed',
};

const _wideBreakpoint = 720.0;
const _readingWidth = 680.0; // the list stops growing here, so rows stay easy to scan

class _FocusQuickAdd extends Intent {
  const _FocusQuickAdd();
}

class _FocusQuickAddAction extends Action<_FocusQuickAdd> {
  _FocusQuickAddAction(this.node);
  final FocusNode node;
  @override
  bool isEnabled(_FocusQuickAdd intent) => !focusInTextField();
  @override
  Object? invoke(_FocusQuickAdd intent) {
    node.requestFocus();
    return null;
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repo, required this.clock, required this.theme, this.onSignOut});

  final TaskRepository repo;
  final Clock clock;
  final ThemeController theme;
  final VoidCallback? onSignOut; // null when there is no account (menu item disabled)

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final AppLifecycleListener _lifecycle;
  final _quickAdd = FocusNode();
  bool _showAllCompleted = false;
  String? _panelId; // task open in the wide-layout side panel
  List<Task> _latest = const [];
  final _pendingDelete = <String>{}; // hidden now, deleted for real when the Undo snackbar closes

  @override
  void initState() {
    super.initState();
    // Re-evaluate "now" when the app comes back to the foreground / regains focus.
    _lifecycle = AppLifecycleListener(onResume: widget.clock.refresh);
    notificationTaps.addListener(_openRequested);
  }

  /// A tapped reminder asks for its task. On a cold start the list may not have loaded yet; it is retried on load.
  void _openRequested() {
    final id = notificationTaps.value;
    final task = id == null ? null : _latest.where((t) => t.id == id).firstOrNull;
    if (task == null || !mounted) return;
    notificationTaps.value = null;
    _open(task, _latest, MediaQuery.sizeOf(context).width >= _wideBreakpoint);
  }

  @override
  void dispose() {
    notificationTaps.removeListener(_openRequested);
    _lifecycle.dispose();
    _quickAdd.dispose();
    super.dispose();
  }

  void _create(String name) {
    final now = widget.clock.value.toUtc();
    widget.repo.upsert(Task(id: newTaskId(), name: name, createdAt: now, updatedAt: now));
  }

  void _toggle(Task t, bool done) {
    widget.clock.refresh();
    widget.repo.upsert(t.copyWith(done: done, doneAt: done ? widget.clock.value : null));
    if (done) _undoable('Completed "${t.name}"', undo: () => widget.repo.upsert(t));
  }

  /// Hard delete, but only once the Undo snackbar has gone away without Undo being pressed.
  void _delete(Task t) {
    setState(() => _pendingDelete.add(t.id));
    _undoable('Deleted "${t.name}"', undo: () {}, onExpire: () => widget.repo.delete(t.id), onClosed: () {
      if (mounted) setState(() => _pendingDelete.remove(t.id));
    });
  }

  void _undoable(String message, {required VoidCallback undo, VoidCallback? onExpire, VoidCallback? onClosed}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger
        .showSnackBar(SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(label: 'Undo', onPressed: undo),
        ))
        .closed
        .then((reason) {
      if (reason != SnackBarClosedReason.action) onExpire?.call();
      onClosed?.call();
    });
  }

  Future<void> _open(Task t, List<Task> all, bool wide) async {
    if (wide) return setState(() => _panelId = t.id);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheet) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheet).viewInsets.bottom),
        child: _detail(t, all, () => Navigator.pop(sheet)),
      ),
    );
  }

  Widget _detail(Task t, List<Task> all, VoidCallback close) => TaskDetail(
        key: ValueKey(t.id),
        task: t,
        knownPeople: knownPeople(all),
        now: widget.clock.value,
        onClose: close,
        onSave: (u) {
          widget.repo.upsert(u);
          close();
        },
        onDelete: () {
          close();
          _delete(t);
        },
      );

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {SingleActivator(LogicalKeyboardKey.keyN): _FocusQuickAdd()},
      child: Actions(
        actions: {_FocusQuickAdd: _FocusQuickAddAction(_quickAdd)},
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(title: const Text('Tasks'), actions: [_PendingBadge(widget.repo.pending), _menu()]),
            body: StreamBuilder<List<Task>>(
              stream: widget.repo.watch(),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final all = snap.data!;
                _latest = all;
                if (notificationTaps.value != null) WidgetsBinding.instance.addPostFrameCallback((_) => _openRequested());
                return LayoutBuilder(builder: (context, box) {
                  final wide = box.maxWidth >= _wideBreakpoint;
                  final open = wide ? all.where((t) => t.id == _panelId).firstOrNull : null;
                  return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: _readingWidth),
                          child: Column(children: [
                            QuickAddBar(onSubmit: _create, focusNode: _quickAdd),
                            Expanded(child: _list(all, wide)),
                          ]),
                        ),
                      ),
                    ),
                    if (open != null) ...[
                      const VerticalDivider(width: 1),
                      SizedBox(width: 380, child: _detail(open, all, () => setState(() => _panelId = null))),
                    ],
                  ]);
                });
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _list(List<Task> all, bool wide) => ValueListenableBuilder<DateTime>(
        valueListenable: widget.clock,
        builder: (context, now, _) {
          final visible = all.where((t) => !_pendingDelete.contains(t.id)).toList();
          final sections = groupTasks(visible, now, showAllCompleted: _showAllCompleted);
          if (sections.isEmpty) return const EmptyState();
          return AnimatedTaskList(entries: [
            for (final e in sections.entries) ...[
              ListEntry(
                'h:${e.key.name}',
                Semantics(
                  header: true,
                  child: Padding(
  padding: const EdgeInsets.fromLTRB(28, 24, 16, 4),
                    child: Text(_titles[e.key]!, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ),
                ),
              ),
              for (final t in e.value)
                // Keyed by section too, so a task changing section animates out of one and into the other.
                ListEntry(
                  '${t.id}@${e.key.name}',
                  TaskRow(
                    task: t,
                    now: now,
                    showDate: e.key == Section.later || e.key == Section.past,
                    onTap: () => _open(t, all, wide),
                    onToggle: (v) => _toggle(t, v),
                  ),
                ),
            ],
          ]);
        },
      );

  Widget _menu() => ValueListenableBuilder<ThemeMode>(
        valueListenable: widget.theme,
        builder: (context, mode, _) => PopupMenuButton<Object>(
          onSelected: (v) {
            if (v is ThemeMode) widget.theme.set(v);
            if (v == 'completed') setState(() => _showAllCompleted = !_showAllCompleted);
            if (v == 'signout') widget.onSignOut?.call();
          },
          itemBuilder: (_) => [
            for (final m in ThemeMode.values)
              CheckedPopupMenuItem<Object>(
                value: m,
                checked: mode == m,
                child: Text(switch (m) { ThemeMode.system => 'System theme', ThemeMode.light => 'Light', ThemeMode.dark => 'Dark' }),
              ),
            const PopupMenuDivider(),
            CheckedPopupMenuItem<Object>(value: 'completed', checked: _showAllCompleted, child: const Text('Show all completed')),
            PopupMenuItem<Object>(value: 'signout', enabled: widget.onSignOut != null, child: const Text('Sign out')),
          ],
        ),
      );
}

/// "offline · N pending" for writes the server hasn't acknowledged. Shown only after 3s, so a normal save doesn't flash it.
class _PendingBadge extends StatefulWidget {
  const _PendingBadge(this.pending);

  final ValueListenable<int> pending;

  @override
  State<_PendingBadge> createState() => _PendingBadgeState();
}

class _PendingBadgeState extends State<_PendingBadge> {
  Timer? _timer;
  bool _show = false;

  @override
  void initState() {
    super.initState();
    widget.pending.addListener(_changed);
    _changed();
  }

  void _changed() {
    if (widget.pending.value == 0) {
      _timer?.cancel();
      _timer = null;
      if (_show) setState(() => _show = false);
      return;
    }
    _timer ??= Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  void dispose() {
    widget.pending.removeListener(_changed);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    return ValueListenableBuilder<int>(
      valueListenable: widget.pending,
      builder: (context, n, _) => Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Chip(
          avatar: const Icon(Icons.cloud_off, size: 16),
          label: Text('offline · $n pending'),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}
