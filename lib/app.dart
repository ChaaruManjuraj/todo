import 'package:flutter/material.dart';

import 'auth/auth_service.dart';
import 'data/task_repository.dart';
import 'ui/clock.dart';
import 'ui/home_screen.dart';
import 'ui/sign_in_screen.dart';
import 'ui/theme.dart';
import 'ui/theme_controller.dart';

class TodoApp extends StatelessWidget {
  /// Either a fixed [repo] (no sign-in), or [auth] + [repoFor] (a repo per signed-in user).
  const TodoApp({super.key, this.repo, required this.clock, required this.theme, this.auth, this.repoFor})
      : assert(repo != null || (auth != null && repoFor != null));

  final TaskRepository? repo;
  final AuthService? auth;
  final TaskRepository Function(String uid)? repoFor;
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
          home: auth == null
              ? HomeScreen(repo: repo!, clock: clock, theme: theme)
              : AuthGate(auth: auth!, repoFor: repoFor!, clock: clock, theme: theme),
        ),
      );
}
