// Copyright 2026 The Pinguteca SDK Authors.
//
// PKCE (RFC 7636) verifier/challenge pair generator. Used by the
// authorization_code flow to bind the authorization request to the
// later code-exchange request without a static client secret.

import 'dart:convert';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Verifier byte length. RFC 7636 §4.1 allows 43-128 base64url characters;
/// 32 raw bytes encodes to exactly 43 base64url characters with no padding,
/// hitting the lower bound and matching what Google, Auth0, Entra ID, and
/// Keycloak suggest in their PKCE samples.
const _verifierByteLength = 32;

/// PKCE code verifier and matching challenge.
///
/// The verifier is a high-entropy secret kept by the client. The
/// challenge is `base64url-no-pad(SHA-256(verifier))`; method is always
/// `S256`. The legacy `plain` method is intentionally not supported -
/// every modern IdP requires `S256` and `plain` defeats the point.
final class PkcePair {
  /// Base64url-encoded random bytes. Send only to the token endpoint
  /// during code exchange.
  final String codeVerifier;

  /// `base64url-no-pad(SHA-256(codeVerifier))`. Send to the
  /// authorization endpoint alongside `code_challenge_method=S256`.
  final String codeChallenge;

  const PkcePair._(this.codeVerifier, this.codeChallenge);

  /// Always `'S256'` per the SDK's policy. Exposed as a constant so
  /// builders can attach it without hard-coding the literal.
  String get codeChallengeMethod => 'S256';

  /// Generates a fresh PKCE pair using `Random.secure()` for entropy.
  /// Backed by the platform CSPRNG (`/dev/urandom`, `BCryptGenRandom`, or
  /// Web Crypto); FIPS-aligned on validated platforms.
  factory PkcePair.generate() {
    final rng = Random.secure();
    final bytes = Uint8List(_verifierByteLength);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = rng.nextInt(256);
    }
    final verifier = _base64UrlNoPad(bytes);
    final challenge = _base64UrlNoPad(
      sha256.convert(utf8.encode(verifier)).bytes,
    );
    return PkcePair._(verifier, challenge);
  }

  /// Reconstructs a pair from an existing [codeVerifier]. Useful when
  /// the verifier was persisted across a process boundary (e.g. the
  /// authorize step and the exchange step run in different processes).
  factory PkcePair.fromVerifier(String codeVerifier) {
    if (codeVerifier.length < 43 || codeVerifier.length > 128) {
      throw ArgumentError.value(
        codeVerifier,
        'codeVerifier',
        'must be 43..128 characters per RFC 7636 §4.1',
      );
    }
    final challenge = _base64UrlNoPad(
      sha256.convert(utf8.encode(codeVerifier)).bytes,
    );
    return PkcePair._(codeVerifier, challenge);
  }
}

String _base64UrlNoPad(List<int> bytes) {
  final encoded = base64Url.encode(bytes);
  return encoded.replaceAll('=', '');
}
