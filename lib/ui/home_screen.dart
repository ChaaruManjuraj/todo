import 'package:flutter/material.dart';

import '../data/task_repository.dart';
import '../domain/schedule.dart';
import '../domain/task.dart';
import 'clock.dart';
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
  bool _showAllCompleted = false;

  @override
  void initState() {
    super.initState();
    // Re-evaluate "now" when the app comes back to the foreground / regains focus.
    _lifecycle = AppLifecycleListener(onResume: widget.clock.refresh);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tasks'), actions: [_menu()]),
      body: StreamBuilder<List<Task>>(
        stream: widget.repo.watch(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return ValueListenableBuilder<DateTime>(
            valueListenable: widget.clock,
            builder: (context, now, _) {
              final sections = groupTasks(snap.data!, now, showAllCompleted: _showAllCompleted);
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
                    ),
                ],
              ]);
            },
          );
        },
      ),
    );
  }

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
