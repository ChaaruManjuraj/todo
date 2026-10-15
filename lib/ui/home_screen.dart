import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/task_repository.dart';
import '../domain/schedule.dart';
import '../domain/task.dart';
import 'clock.dart';
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
  const HomeScreen({super.key, required this.repo, required this.clock, required this.theme});

  final TaskRepository repo;
  final Clock clock;
  final ThemeController theme;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final AppLifecycleListener _lifecycle;
  final _quickAdd = FocusNode();
  bool _showAllCompleted = false;
  String? _panelId; // task open in the wide-layout side panel

  @override
  void initState() {
    super.initState();
    // Re-evaluate "now" when the app comes back to the foreground / regains focus.
    _lifecycle = AppLifecycleListener(onResume: widget.clock.refresh);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _quickAdd.dispose();
    super.dispose();
  }

  void _create(String name) {
    final now = widget.clock.value.toUtc();
    widget.repo.upsert(Task(id: newTaskId(), name: name, createdAt: now, updatedAt: now));
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
          widget.repo.delete(t.id);
          close();
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
            appBar: AppBar(title: const Text('Tasks'), actions: [_menu()]),
            body: StreamBuilder<List<Task>>(
              stream: widget.repo.watch(),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final all = snap.data!;
                return LayoutBuilder(builder: (context, box) {
                  final wide = box.maxWidth >= _wideBreakpoint;
                  final open = wide ? all.where((t) => t.id == _panelId).firstOrNull : null;
                  return Row(children: [
                    Expanded(
                      child: Column(children: [
                        QuickAddBar(onSubmit: _create, focusNode: _quickAdd),
                        Expanded(child: _list(all, wide)),
                      ]),
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
          final sections = groupTasks(all, now, showAllCompleted: _showAllCompleted);
          if (sections.isEmpty) return const Center(child: Text('Nothing to do'));
          return ListView(children: [
            for (final e in sections.entries) ...[
              Semantics(
                header: true,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                  child: Text(_titles[e.key]!, style: Theme.of(context).textTheme.titleSmall),
                ),
              ),
              for (final t in e.value)
                TaskRow(
                  key: ValueKey(t.id),
                  task: t,
                  now: now,
                  showDate: e.key == Section.later || e.key == Section.past,
                  onTap: () => _open(t, all, wide),
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
            const PopupMenuItem<Object>(enabled: false, child: Text('Sign out')), // wired in slice 7
          ],
        ),
      );
}
