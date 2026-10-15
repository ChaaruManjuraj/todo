import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'auth/firebase_auth_service.dart';
import 'data/firestore_repo.dart';
import 'data/memory_repo.dart';
import 'firebase_options.dart';
import 'ui/clock.dart';
import 'ui/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final theme = await ThemeController.load();
  final clock = Clock();

  final flutterFire = kIsWeb || defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.macOS;
  if (flutterFire) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    runApp(TodoApp(clock: clock, theme: theme, auth: FirebaseAuthService(), repoFor: (uid) => FirestoreRepo(uid)));
  } else {
    // Windows and Linux get their own auth + data path in slice 8; until then, in-memory.
    runApp(TodoApp(repo: MemoryRepo(), clock: clock, theme: theme));
  }
}
