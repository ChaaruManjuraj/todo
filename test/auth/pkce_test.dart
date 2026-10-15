import 'package:flutter_test/flutter_test.dart';
import 'package:todo/auth/pkce.dart';

void main() {
  test('S256 challenge matches the RFC 7636 appendix B test vector', () {
    expect(codeChallenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'), 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
  });

  test('a verifier is 43 URL-safe characters (RFC 7636 §4.1) and never repeats', () {
    final a = newCodeVerifier(), b = newCodeVerifier();
    expect(a, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    expect(a, isNot(b));
  });

  test('state values are URL-safe and never repeat', () {
    final a = newState(), b = newState();
    expect(a, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    expect(a, isNot(b));
  });

  test('the challenge has no padding', () {
    expect(codeChallenge(newCodeVerifier()).contains('='), isFalse);
  });
}
