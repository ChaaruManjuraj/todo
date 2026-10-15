import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todo/auth/desktop_auth_service.dart';
import 'package:todo/auth/pkce.dart';

/// Fake Google + Identity Toolkit + Secure Token endpoints.
class FakeGoogle {
  final requests = <http.Request>[];
  bool offline = false;
  int refreshStatus = 200;
  String refreshError = '';
  int expiresIn = 3600;
  var refreshCount = 0;

  http.Response _json(Object j, [int status = 200]) => http.Response(jsonEncode(j), status, headers: {'content-type': 'application/json'});

  Future<http.Response> handle(http.Request r) async {
    requests.add(r);
    if (offline) throw http.ClientException('offline');
    switch (r.url.host) {
      case 'oauth2.googleapis.com':
        return _json({'id_token': 'google-id-token', 'access_token': 'x'});
      case 'identitytoolkit.googleapis.com':
        return _json({'idToken': 'fb-id-1', 'refreshToken': 'refresh-1', 'expiresIn': '$expiresIn', 'localId': 'uid-1'});
      case 'securetoken.googleapis.com':
        refreshCount++;
        if (refreshStatus != 200) return _json({'error': {'message': refreshError}}, refreshStatus);
        return _json({'id_token': 'fb-id-${refreshCount + 1}', 'refresh_token': 'refresh-${refreshCount + 1}', 'expires_in': '$expiresIn', 'user_id': 'uid-1'});
    }
    return _json({}, 404);
  }

  http.Request to(String host) => requests.singleWhere((r) => r.url.host == host);
}

/// Plays the browser: hit the loopback redirect the service is listening on.
Future<int> visit(String redirect, Map<String, String> query, {String path = ''}) async {
  final c = HttpClient();
  try {
    final req = await c.getUrl(Uri.parse('$redirect$path').replace(queryParameters: query));
    final res = await req.close();
    await res.drain<void>();
    return res.statusCode;
  } finally {
    c.close(force: true);
  }
}

void main() {
  late FakeGoogle google;
  late MemoryTokenStore store;
  late DateTime clock;
  Uri? launched;

  DesktopAuthService make({Future<bool> Function(Uri)? launch, String clientId = 'cid', Duration timeout = const Duration(seconds: 5)}) => DesktopAuthService(
        client: MockClient(google.handle),
        clientId: clientId,
        clientSecret: 'csecret',
        apiKey: 'api-key',
        store: store,
        launch: launch ??
            (url) async {
              launched = url;
              final q = url.queryParameters;
              unawaited(visit(q['redirect_uri']!, {'code': 'auth-code', 'state': q['state']!}));
              return true;
            },
        now: () => clock,
        signInTimeout: timeout,
      );

  setUp(() {
    google = FakeGoogle();
    store = MemoryTokenStore();
    clock = DateTime.utc(2026, 10, 15, 12);
    launched = null;
  });

  group('signIn', () {
    test('runs the whole OAuth + Firebase exchange and emits the uid', () async {
      final auth = make();
      final uids = <String?>[];
      final sub = auth.uid().listen(uids.add);
      await Future<void>.delayed(Duration.zero);
      await auth.signIn();
      await Future<void>.delayed(Duration.zero);
      expect(uids, [null, 'uid-1']);
      await sub.cancel();

      final q = launched!.queryParameters;
      expect(launched!.host, 'accounts.google.com');
      expect([q['client_id'], q['response_type'], q['code_challenge_method']], ['cid', 'code', 'S256']);
      expect(q['scope'], contains('openid'));
      expect(q['redirect_uri'], startsWith('http://127.0.0.1:'));

      final exchange = Uri.splitQueryString(google.to('oauth2.googleapis.com').body);
      expect(exchange['code'], 'auth-code');
      expect(exchange['client_secret'], 'csecret');
      expect(exchange['redirect_uri'], q['redirect_uri']);
      expect(codeChallenge(exchange['code_verifier']!), q['code_challenge'], reason: 'the verifier must match the challenge that was sent');

      final fb = google.to('identitytoolkit.googleapis.com');
      expect(fb.url.path, endsWith('accounts:signInWithIdp'));
      expect(fb.url.queryParameters['key'], 'api-key');
      expect((jsonDecode(fb.body) as Map)['postBody'], 'id_token=google-id-token&providerId=google.com');
    });

    test('only the refresh token and uid are persisted', () async {
      await make().signIn();
      expect(store.map, {'uid': 'uid-1', 'refreshToken': 'refresh-1'});
    });

    test('a stray or forged request to the loopback port is ignored; the real redirect still works', () async {
      final auth = make(launch: (url) async {
        final q = url.queryParameters;
        unawaited(() async {
          expect(await visit(q['redirect_uri']!, {}, path: 'favicon.ico'), 400);
          expect(await visit(q['redirect_uri']!, {'code': 'evil', 'state': 'wrong'}), 400);
          await visit(q['redirect_uri']!, {'code': 'auth-code', 'state': q['state']!});
        }());
        return true;
      });
      await auth.signIn();
      expect(Uri.splitQueryString(google.to('oauth2.googleapis.com').body)['code'], 'auth-code');
    });

    test('the user declining returns normally and signs nobody in', () async {
      final auth = make(launch: (url) async {
        final q = url.queryParameters;
        unawaited(visit(q['redirect_uri']!, {'error': 'access_denied', 'state': q['state']!}));
        return true;
      });
      final uids = <String?>[];
      final sub = auth.uid().listen(uids.add);
      await auth.signIn();
      await Future<void>.delayed(Duration.zero);
      expect(uids, [null]);
      expect(google.requests, isEmpty);
      await sub.cancel();
    });

    test('gives up and frees the port if the browser never comes back', () async {
      Uri? url;
      final auth = make(timeout: const Duration(milliseconds: 100), launch: (u) async {
        url = u;
        return true;
      });
      await expectLater(auth.signIn(), throwsA(isA<TimeoutException>()));
      final redirect = url!.queryParameters['redirect_uri']!;
      await expectLater(visit(redirect, {}), throwsA(isA<SocketException>()), reason: 'the loopback server should be closed');
    });

    test('a browser that cannot be opened is reported', () async {
      await expectLater(make(launch: (_) async => false).signIn(), throwsA(isA<Exception>()));
    });

    test('refuses to start without an OAuth client configured', () async {
      await expectLater(make(clientId: '').signIn(), throwsA(isA<Exception>()));
      expect(google.requests, isEmpty);
    });
  });

  group('idToken', () {
    test('is cached until 5 minutes before expiry', () async {
      final auth = make();
      await auth.signIn();
      expect(await auth.idToken(), 'fb-id-1');
      expect(google.refreshCount, 0);
      clock = clock.add(const Duration(minutes: 54)); // 6 min left
      expect(await auth.idToken(), 'fb-id-1');
      expect(google.refreshCount, 0);
      clock = clock.add(const Duration(minutes: 2)); // 4 min left
      expect(await auth.idToken(), 'fb-id-2');
      expect(google.refreshCount, 1);
    });

    test('forceRefresh always refreshes, and the rotated refresh token is saved', () async {
      final auth = make();
      await auth.signIn();
      expect(await auth.idToken(forceRefresh: true), 'fb-id-2');
      expect(store.map['refreshToken'], 'refresh-2');
      final body = Uri.splitQueryString(google.requests.last.body);
      expect([body['grant_type'], body['refresh_token']], ['refresh_token', 'refresh-1']);
    });

    test('simultaneous callers share one refresh', () async {
      final auth = make();
      await auth.signIn();
      clock = clock.add(const Duration(hours: 2));
      final tokens = await Future.wait([auth.idToken(), auth.idToken(), auth.idToken()]);
      expect(tokens.toSet().length, 1);
      expect(google.refreshCount, 1);
    });

    test('a refused refresh token signs out and clears the keychain', () async {
      final auth = make();
      await auth.signIn();
      final uids = <String?>[];
      final sub = auth.uid().listen(uids.add);
      await Future<void>.delayed(Duration.zero);
      google
        ..refreshStatus = 400
        ..refreshError = 'INVALID_REFRESH_TOKEN';
      await expectLater(auth.idToken(forceRefresh: true), throwsA(isA<Exception>()));
      await Future<void>.delayed(Duration.zero);
      expect(uids.last, isNull);
      expect(store.map, isEmpty);
      await sub.cancel();
    });

    test('being offline throws but keeps you signed in', () async {
      final auth = make();
      await auth.signIn();
      google.offline = true;
      await expectLater(auth.idToken(forceRefresh: true), throwsA(isA<Exception>()));
      expect(store.map['refreshToken'], 'refresh-1');
      google.offline = false;
      expect(await auth.idToken(forceRefresh: true), 'fb-id-2');
    });

    test('a server error also keeps the session', () async {
      final auth = make();
      await auth.signIn();
      google.refreshStatus = 503;
      await expectLater(auth.idToken(forceRefresh: true), throwsA(isA<Exception>()));
      expect(store.map['uid'], 'uid-1');
    });

    test('throws when nobody is signed in', () async {
      await expectLater(make().idToken(), throwsA(isA<Exception>()));
    });
  });

  test('a saved session is restored on startup without any network', () async {
    store.map.addAll({'uid': 'uid-9', 'refreshToken': 'r'});
    google.offline = true;
    expect(await make().uid().first, 'uid-9');
    expect(google.requests, isEmpty);
  });

  test('signed out at startup emits null', () async {
    expect(await make().uid().first, isNull);
  });

  test('signOut clears the keychain and emits null', () async {
    final auth = make();
    await auth.signIn();
    final uids = <String?>[];
    final sub = auth.uid().listen(uids.add);
    await Future<void>.delayed(Duration.zero);
    await auth.signOut();
    await Future<void>.delayed(Duration.zero);
    expect(uids, ['uid-1', null]);
    expect(store.map, isEmpty);
    await expectLater(auth.idToken(), throwsA(isA<Exception>()));
    await sub.cancel();
  });
}
