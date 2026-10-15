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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Image.asset('assets/logo/logo.png', width: 72, height: 72, semanticLabel: 'TODO'),
                ),
                const SizedBox(height: 28),
                Text('Your tasks, everywhere.', style: text.displaySmall),
                const SizedBox(height: 10),
                Text('Sign in once and your list follows you from your phone to your desk.',
                    style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: _busy ? null : _signIn,
                  icon: _busy
                      ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onSurfaceVariant))
                      : const Icon(Icons.login_rounded),
                  label: const Text('Sign in with Google'),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Semantics(
                      liveRegion: true,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(Icons.error_outline_rounded, size: 20, color: scheme.onErrorContainer),
                          const SizedBox(width: 10),
                          Expanded(child: Text(_error!, style: text.bodyMedium?.copyWith(color: scheme.onErrorContainer))),
                        ]),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
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
