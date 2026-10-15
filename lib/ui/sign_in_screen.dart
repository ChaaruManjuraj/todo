import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../data/task_repository.dart';
import 'clock.dart';
import 'home_screen.dart';
import 'theme_controller.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.signIn();
    } catch (e) {
      if (mounted) setState(() => _error = 'Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('TODO', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text('Your tasks, on every device.', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: _busy ? null : _signIn,
                  icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.login),
                  label: const Text('Sign in with Google'),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Semantics(liveRegion: true, child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                  ),
              ]),
            ),
          ),
        ),
      );
}

/// Sign-in screen while signed out; the task list (backed by a repo for that user) once signed in.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.auth, required this.repoFor, required this.clock, required this.theme});

  final AuthService auth;
  final TaskRepository Function(String uid) repoFor;
  final Clock clock;
  final ThemeController theme;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Stream<String?> _uid = widget.auth.uid();
  String? _repoUid;
  TaskRepository? _repo;

  @override
  Widget build(BuildContext context) => StreamBuilder<String?>(
        stream: _uid,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          final uid = snap.data;
          if (uid == null) return SignInScreen(auth: widget.auth);
          if (uid != _repoUid) {
            _repoUid = uid;
            _repo = widget.repoFor(uid);
          }
          return HomeScreen(key: ValueKey(uid), repo: _repo!, clock: widget.clock, theme: widget.theme, onSignOut: widget.auth.signOut);
        },
      );
}
