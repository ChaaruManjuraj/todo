import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'pkce.dart';

abstract class TokenStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// OS keychain: libsecret on Linux, Credential Manager on Windows.
class SecureTokenStore implements TokenStore {
  const SecureTokenStore();
  static const _s = FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

class MemoryTokenStore implements TokenStore {
  final map = <String, String>{};
  @override
  Future<String?> read(String key) async => map[key];
  @override
  Future<void> write(String key, String value) async => map[key] = value;
  @override
  Future<void> delete(String key) async => map.remove(key);
}

const _sessionGone = {'TOKEN_EXPIRED', 'INVALID_REFRESH_TOKEN', 'USER_DISABLED', 'USER_NOT_FOUND'};

/// Windows/Linux sign-in: Google OAuth in the system browser (loopback redirect + PKCE), exchanged for a Firebase
/// session through Identity Toolkit. Only the refresh token is persisted, in the OS keychain.
class DesktopAuthService implements AuthService {
  DesktopAuthService({
    required this.client,
    required this.clientId,
    required this.clientSecret,
    required this.apiKey,
    required this.store,
    required this.launch,
    DateTime Function()? now,
    this.signInTimeout = const Duration(minutes: 5),
  }) : _now = now ?? DateTime.now;

  final http.Client client;
  final String clientId, clientSecret, apiKey;
  final TokenStore store;
  final Future<bool> Function(Uri url) launch;
  final Duration signInTimeout;
  final DateTime Function() _now;

  String? _uid, _refreshToken, _idToken;
  DateTime _expiry = DateTime.fromMillisecondsSinceEpoch(0);
  Future<String>? _refreshing;
  final _changes = StreamController<String?>.broadcast();
  late final Future<void> _ready = _restore();

  Future<void> _restore() async {
    final uid = await store.read('uid');
    final token = await store.read('refreshToken');
    if (uid != null && token != null) {
      _uid = uid; // works offline: the ID token is only fetched when something needs the network
      _refreshToken = token;
    }
  }

  @override
  Stream<String?> uid() => Stream.multi((c) async {
        await _ready;
        c.add(_uid);
        final sub = _changes.stream.listen(c.add);
        c.onCancel = sub.cancel;
      });

  // ---- sign in ---------------------------------------------------------------------------------

  @override
  Future<void> signIn() async {
    if (clientId.isEmpty || clientSecret.isEmpty) {
      throw Exception('Desktop sign-in is not configured. Build with --dart-define=GOOGLE_DESKTOP_CLIENT_ID=... '
          'and --dart-define=GOOGLE_DESKTOP_CLIENT_SECRET=...');
    }
    final verifier = newCodeVerifier();
    final state = newState();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final redirect = 'http://127.0.0.1:${server.port}/';
      final waiting = _awaitCode(server, state); // listening before the browser opens, so the redirect can't be missed
      waiting.ignore(); // if we bail out before awaiting it (browser failed to open), closing the server errors it; that's expected
      final opened = await launch(Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': clientId,
        'redirect_uri': redirect,
        'response_type': 'code',
        'scope': 'openid email profile',
        'code_challenge': codeChallenge(verifier),
        'code_challenge_method': 'S256',
        'state': state,
      }));
      if (!opened) throw Exception('Could not open the browser for sign-in');
      final code = await waiting.timeout(signInTimeout);
      if (code == null) return; // the user cancelled

      final google = await client.post(Uri.https('oauth2.googleapis.com', '/token'), body: {
        'code': code,
        'client_id': clientId,
        'client_secret': clientSecret,
        'redirect_uri': redirect,
        'grant_type': 'authorization_code',
        'code_verifier': verifier,
      });
      if (google.statusCode != 200) throw Exception('Google sign-in failed (HTTP ${google.statusCode})');
      final googleIdToken = (jsonDecode(google.body) as Map)['id_token'] as String;

      final fb = await client.post(
        Uri.https('identitytoolkit.googleapis.com', '/v1/accounts:signInWithIdp', {'key': apiKey}),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'postBody': 'id_token=$googleIdToken&providerId=google.com',
          'requestUri': 'http://localhost',
          'returnIdpCredential': true,
          'returnSecureToken': true,
        }),
      );
      if (fb.statusCode != 200) throw Exception('Firebase sign-in failed (HTTP ${fb.statusCode}): ${_errorMessage(fb.body)}');
      final j = (jsonDecode(fb.body) as Map).cast<String, Object?>();
      await _adopt(uid: j['localId'] as String, refreshToken: j['refreshToken'] as String, idToken: j['idToken'] as String, expiresIn: j['expiresIn']);
      _changes.add(_uid);
    } finally {
      await server.close(force: true);
    }
  }

  /// The authorization code from the redirect, or null if the user declined. Anything that isn't the real redirect
  /// (favicon requests, other local programs, a wrong `state`) is answered and ignored.
  Future<String?> _awaitCode(HttpServer server, String state) async {
    await for (final req in server) {
      final q = req.uri.queryParameters;
      Future<void> reply(int status, String text) async {
        req.response
          ..statusCode = status
          ..headers.contentType = ContentType.html
          ..write('<!doctype html><meta charset="utf-8"><title>TODO</title><body style="font-family:sans-serif;padding:2rem">$text</body>');
        await req.response.close();
      }

      if (req.uri.path != '/' || q['state'] != state) {
        await reply(400, 'Not the sign-in response.');
        continue;
      }
      if (q['error'] != null) {
        await reply(200, 'Sign-in cancelled. You can close this tab.');
        if (q['error'] == 'access_denied') return null;
        throw Exception('Google sign-in error: ${q['error']}');
      }
      if (q['code'] != null) {
        await reply(200, 'Signed in. You can close this tab and return to TODO.');
        return q['code'];
      }
      await reply(400, 'Missing code.');
    }
    throw Exception('Sign-in was interrupted');
  }

  // ---- tokens ----------------------------------------------------------------------------------

  /// A valid Firebase ID token, refreshed when it is within 5 minutes of expiring (or on [forceRefresh]).
  /// Connectivity errors propagate and keep the session; a refused refresh token signs out.
  Future<String> idToken({bool forceRefresh = false}) async {
    await _ready;
    if (_uid == null || _refreshToken == null) throw Exception('Not signed in');
    if (!forceRefresh && _idToken != null && _expiry.difference(_now()) > const Duration(minutes: 5)) return _idToken!;
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<String> _refresh() async {
    final r = await client.post(
      Uri.https('securetoken.googleapis.com', '/v1/token', {'key': apiKey}),
      body: {'grant_type': 'refresh_token', 'refresh_token': _refreshToken!},
    );
    if (r.statusCode != 200) {
      if (r.statusCode == 400 && _sessionGone.contains(_errorMessage(r.body))) {
        await _clear();
        _changes.add(null); // the outbox stays on disk; it syncs next time this account signs in
        throw Exception('Session expired');
      }
      throw Exception('Token refresh failed (HTTP ${r.statusCode})');
    }
    final j = (jsonDecode(r.body) as Map).cast<String, Object?>();
    await _adopt(uid: j['user_id'] as String, refreshToken: j['refresh_token'] as String, idToken: j['id_token'] as String, expiresIn: j['expires_in']);
    return _idToken!;
  }

  Future<void> _adopt({required String uid, required String refreshToken, required String idToken, required Object? expiresIn}) async {
    _uid = uid;
    _refreshToken = refreshToken;
    _idToken = idToken;
    _expiry = _now().add(Duration(seconds: int.parse('$expiresIn')));
    await store.write('uid', uid);
    await store.write('refreshToken', refreshToken);
  }

  String _errorMessage(String body) {
    try {
      return ((jsonDecode(body) as Map)['error'] as Map)['message'] as String;
    } catch (_) {
      return '';
    }
  }

  Future<void> _clear() async {
    _uid = _refreshToken = _idToken = null;
    _expiry = DateTime.fromMillisecondsSinceEpoch(0);
    await store.delete('uid');
    await store.delete('refreshToken');
  }

  @override
  Future<void> signOut() async {
    await _ready;
    await _clear();
    _changes.add(null);
  }
}
