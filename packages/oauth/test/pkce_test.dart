// Copyright 2026 The Pinguteca SDK Authors.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sdk_core_dart_oauth/sdk_core_dart_oauth.dart';
import 'package:test/test.dart';

void main() {
  group('PkcePair.generate', () {
    test('verifier is 43 base64url characters', () {
      final pair = PkcePair.generate();
      expect(pair.codeVerifier.length, 43);
      expect(pair.codeVerifier, matches(r'^[A-Za-z0-9_-]+$'));
    });

    test('challenge is base64url-no-pad SHA-256 of verifier', () {
      final pair = PkcePair.generate();
      final expected = base64Url
          .encode(sha256.convert(utf8.encode(pair.codeVerifier)).bytes)
          .replaceAll('=', '');
      expect(pair.codeChallenge, expected);
    });

    test('two pairs differ', () {
      final a = PkcePair.generate();
      final b = PkcePair.generate();
      expect(a.codeVerifier, isNot(b.codeVerifier));
      expect(a.codeChallenge, isNot(b.codeChallenge));
    });

    test('method is always S256', () {
      expect(PkcePair.generate().codeChallengeMethod, 'S256');
    });
  });

  group('PkcePair.fromVerifier', () {
    test('reconstructs the same challenge from a given verifier', () {
      final original = PkcePair.generate();
      final reconstructed = PkcePair.fromVerifier(original.codeVerifier);
      expect(reconstructed.codeChallenge, original.codeChallenge);
    });

    test('rejects verifiers shorter than 43 chars', () {
      expect(() => PkcePair.fromVerifier('too-short'), throwsArgumentError);
    });

    test('rejects verifiers longer than 128 chars', () {
      final tooLong = 'A' * 129;
      expect(() => PkcePair.fromVerifier(tooLong), throwsArgumentError);
    });
  });
}
