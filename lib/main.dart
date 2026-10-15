import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app.dart';
import 'auth/desktop_auth_service.dart';
import 'auth/firebase_auth_service.dart';
import 'data/firestore_repo.dart';
import 'data/rest_repo.dart';
import 'firebase_options.dart';
import 'ui/clock.dart';
import 'ui/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final theme = await ThemeController.load();
  final clock = Clock();

  // Firebase.initializeApp is only needed for the FlutterFire platforms; the desktop path uses plain HTTPS.
  final flutterFire = kIsWeb || defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.macOS;
  if (flutterFire) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    runApp(TodoApp(clock: clock, theme: theme, auth: FirebaseAuthService(), repoFor: (uid) => FirestoreRepo(uid)));
  } else {
    // Windows and Linux: Google sign-in through the system browser, Firestore over REST with a local cache.
    final support = await getApplicationSupportDirectory();
    final client = http.Client();
    final auth = DesktopAuthService(
      client: client,
      clientId: const String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_ID'),
      clientSecret: const String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_SECRET'),
      apiKey: DefaultFirebaseOptions.web.apiKey,
      store: const SecureTokenStore(),
      launch: (url) => launchUrl(url, mode: LaunchMode.externalApplication),
    );
    // One repo per account for the life of the app, so signing out and back in never opens the same cache twice.
    final repos = <String, RestRepo>{};
    runApp(TodoApp(
      clock: clock,
      theme: theme,
      auth: auth,
      repoFor: (uid) => repos.putIfAbsent(
        uid,
        () => RestRepo.open(client: client, idToken: auth.idToken, cacheDir: Directory('${support.path}/$uid'), uid: uid),
      ),
    ));
  }
}
