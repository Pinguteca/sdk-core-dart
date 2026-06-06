// Copyright 2026 The Pinguteca SDK Authors.
//
// Connect interceptor that injects an `idempotency-key` header on every
// IDEMPOTENT unary call. The key is generated once for the original request
// object, so retries (which call next() repeatedly with the same Request)
// replay the same key and the server can deduplicate.
//
// Pairs with the retry interceptor: per RFC 0002, the composition order is
// `OTel -> Breaker -> Idempotency -> Retry -> Auth`, so this interceptor
// runs once per logical call and retry reuses the request it observes.

import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:connectrpc/connect.dart';

/// Conventional header name. Lowercase per Headers normalization.
const idempotencyKeyHeader = 'idempotency-key';

/// Tuning knobs for [idempotencyKeyInterceptor].
final class IdempotencyConfig {
  /// Header to set. Override only when the server expects a non-standard
  /// name (e.g. `x-idempotency-key`).
  final String headerName;

  /// Source of the key value. Defaults to [defaultIdempotencyKeyGenerator],
  /// which emits a 128-bit hex string seeded by `Random.secure`.
  final String Function()? keyGenerator;

  /// When true, set the key on NO_SIDE_EFFECTS methods too. Default false:
  /// methods without side effects are safe to retry without dedup, so the
  /// header would only add noise. Flip on for correlation use cases.
  final bool includeNoSideEffects;

  /// Builds a config with defaults: lowercase `idempotency-key` header,
  /// crypto-secure 128-bit hex generator, IDEMPOTENT methods only.
  const IdempotencyConfig({
    this.headerName = idempotencyKeyHeader,
    this.keyGenerator,
    this.includeNoSideEffects = false,
  });
}

/// Builds an [Interceptor] that injects an idempotency key into IDEMPOTENT
/// unary calls.
///
/// Skips:
/// - Streaming RPCs (Connect-Dart cannot replay them).
/// - Methods without an `idempotency_level` annotation (the schema did not
///   promise dedup; a key would be misleading).
/// - Methods that already carry the header (caller- or composed-op-supplied
///   keys win, e.g. per-leg keys derived as `{op_id}/{leg_index}`).
/// - NO_SIDE_EFFECTS methods, unless `includeNoSideEffects: true`.
Interceptor idempotencyKeyInterceptor([
  IdempotencyConfig config = const IdempotencyConfig(),
]) {
  final generator = config.keyGenerator ?? defaultIdempotencyKeyGenerator;
  return <I extends Object, O extends Object>(AnyFn<I, O> next) {
    return (Request<I, O> req) {
      if (req.spec.streamType != StreamType.unary) {
        return next(req);
      }
      final level = req.spec.idempotency;
      if (level == null) {
        return next(req);
      }
      if (level == Idempotency.noSideEffects && !config.includeNoSideEffects) {
        return next(req);
      }
      if (req.headers[config.headerName] != null) {
        return next(req);
      }
      req.headers[config.headerName] = generator();
      return next(req);
    };
  };
}

/// Emits a 128-bit hex-encoded key from `Random.secure()`, which uses the
/// platform CSPRNG (`/dev/urandom`, `BCryptGenRandom`, or Web Crypto).
/// FIPS 140-3 aligned on validated platforms.
String defaultIdempotencyKeyGenerator() {
  final rng = Random.secure();
  final bytes = Uint8List(16);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = rng.nextInt(256);
  }
  final buffer = StringBuffer();
  for (final b in bytes) {
    buffer.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
