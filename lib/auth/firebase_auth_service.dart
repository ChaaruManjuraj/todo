import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../firebase_options.dart';
import 'auth_service.dart';

/// Android and macOS go through `google_sign_in`; web uses the Firebase popup.
class FirebaseAuthService implements AuthService {
  FirebaseAuthService({FirebaseAuth? auth, GoogleSignIn? google})
      : _auth = auth ?? FirebaseAuth.instance,
        _google = google ?? GoogleSignIn(clientId: defaultTargetPlatform == TargetPlatform.macOS ? DefaultFirebaseOptions.macos.iosClientId : null);

  final FirebaseAuth _auth;
  final GoogleSignIn _google;

  @override
  Stream<String?> uid() => _auth.authStateChanges().map((u) => u?.uid);

  @override
  Future<void> signIn() async {
    if (kIsWeb) {
      await _auth.signInWithPopup(GoogleAuthProvider());
      return;
    }
    final account = await _google.signIn();
    if (account == null) return; // cancelled
    final tokens = await account.authentication;
    await _auth.signInWithCredential(GoogleAuthProvider.credential(accessToken: tokens.accessToken, idToken: tokens.idToken));
  }

  @override
  Future<void> signOut() async {
    if (!kIsWeb) await _google.signOut();
    await _auth.signOut();
  }
}
