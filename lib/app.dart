import 'package:flutter/material.dart';

import 'data/task_repository.dart';
import 'ui/clock.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';
import 'ui/theme_controller.dart';

class TodoApp extends StatelessWidget {
  const TodoApp({super.key, required this.repo, required this.clock, required this.theme});

  final TaskRepository repo;
  final Clock clock;
  final ThemeController theme;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
        valueListenable: theme,
        builder: (context, mode, _) => MaterialApp(
          title: 'TODO',
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: mode,
          home: HomeScreen(repo: repo, clock: clock, theme: theme),
        ),
      );
}
