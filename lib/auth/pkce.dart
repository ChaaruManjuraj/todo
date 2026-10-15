import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

String _random(int bytes) {
  final r = Random.secure();
  return _b64([for (var i = 0; i < bytes; i++) r.nextInt(256)]);
}

/// RFC 7636 §4.1: 43 URL-safe characters from 32 random bytes.
String newCodeVerifier() => _random(32);

/// OAuth `state`: ties the redirect back to the request that started it.
String newState() => _random(16);

/// RFC 7636 §4.2 (S256): BASE64URL(SHA256(verifier)) without padding.
String codeChallenge(String verifier) => _b64(sha256.convert(ascii.encode(verifier)).bytes);
