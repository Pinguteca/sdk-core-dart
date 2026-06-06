// Copyright 2026 The Pinguteca SDK Authors.
//
// Configuration for the retry interceptor. The user-visible contract is pinned
// in sdk-scaffold/docs/rfc/0006-retry-behavioural-contract.md; this file is
// the Dart-side implementation of those defaults.

import 'dart:math' show Random;

import 'package:connectrpc/connect.dart';

/// Jitter scheme for retry delays.
enum RetryStrategy {
  /// AWS full jitter: `delay = MinDelay + rand(0, max(0, ceiling - MinDelay))`,
  /// where `ceiling` grows by [RetryConfig.multiplier] each attempt. Best
  /// general-purpose choice.
  full,

  /// AWS decorrelated jitter:
  /// `delay = Initial + rand(0, max(0, min(Max, prev * DecorrelationFactor) - Initial))`.
  /// Bounds the next delay relative to the previous one. Useful under
  /// sustained load where the attempt counter loses meaning. Ignores
  /// [RetryConfig.minDelay]; its floor is always [RetryConfig.initial].
  decorrelated,
}

/// Retryable status codes per RFC 0006. Exposed for callers building a
/// custom [RetryConfig.isRetryable] predicate that delegates to the default
/// set.
const defaultRetryableCodes = <Code>{
  Code.unavailable,
  Code.resourceExhausted,
  Code.aborted,
  Code.deadlineExceeded,
};

/// Recommended defaults: 4 attempts, 100ms initial, 30s max, full jitter,
/// retry on the four transient codes above. Override individual fields via
/// the named parameters.
final class RetryConfig {
  /// Maximum attempts, including the first call. RFC 0006 default is 4.
  /// Clamped to a minimum of 2 by the interceptor.
  final int maxAttempts;

  /// Initial backoff floor and seed for the per-attempt ceiling.
  final Duration initial;

  /// Maximum local backoff. Does not clamp server-supplied retry hints.
  final Duration max;

  /// Optional floor for [RetryStrategy.full]. Ignored by
  /// [RetryStrategy.decorrelated], whose floor is always [initial].
  final Duration minDelay;

  /// Growth factor applied to the per-attempt ceiling under
  /// [RetryStrategy.full].
  final double multiplier;

  /// Bound for [RetryStrategy.decorrelated]: each draw is taken from
  /// `[initial, prev * decorrelationFactor]`.
  final double decorrelationFactor;

  /// Jitter scheme selecting between full and decorrelated.
  final RetryStrategy strategy;

  /// When true (default), a server-supplied `retry-after` header or
  /// `google.rpc.RetryInfo` detail overrides the locally-computed backoff.
  final bool honorRetryAfter;

  /// Bypass the schema-driven idempotency safety gate. Default false:
  /// methods without `idempotency_level = IDEMPOTENT` (or `NO_SIDE_EFFECTS`)
  /// are not retried. Set true only when paired with an idempotency-key
  /// interceptor and a server that deduplicates by key.
  final bool allowNonIdempotent;

  /// Status codes that trigger a retry when [isRetryable] is null.
  final Set<Code> retryableCodes;

  /// Custom predicate, overriding [retryableCodes] when non-null.
  final bool Function(ConnectException error)? isRetryable;

  /// Source of the uniform `[0.0, 1.0)` jitter draw. Defaults to
  /// [defaultJitterSource] (`Random.secure`).
  final double Function()? jitterSource;

  /// Hook used to pause between attempts. Defaults to [Future.delayed].
  /// Tests inject a fake to capture the requested delay sequence.
  final Future<void> Function(Duration delay)? sleep;

  /// Builds a [RetryConfig] with RFC 0006 defaults.
  const RetryConfig({
    this.maxAttempts = 4,
    this.initial = const Duration(milliseconds: 100),
    this.max = const Duration(seconds: 30),
    this.minDelay = Duration.zero,
    this.multiplier = 2.0,
    this.decorrelationFactor = 3.0,
    this.strategy = RetryStrategy.full,
    this.honorRetryAfter = true,
    this.allowNonIdempotent = false,
    this.retryableCodes = defaultRetryableCodes,
    this.isRetryable,
    this.jitterSource,
    this.sleep,
  });

  /// Returns a copy with the given fields overridden. Mirrors the Go
  /// implementation's pattern of starting from defaults and tweaking.
  RetryConfig copyWith({
    int? maxAttempts,
    Duration? initial,
    Duration? max,
    Duration? minDelay,
    double? multiplier,
    double? decorrelationFactor,
    RetryStrategy? strategy,
    bool? honorRetryAfter,
    bool? allowNonIdempotent,
    Set<Code>? retryableCodes,
    bool Function(ConnectException error)? isRetryable,
    double Function()? jitterSource,
    Future<void> Function(Duration delay)? sleep,
  }) {
    return RetryConfig(
      maxAttempts: maxAttempts ?? this.maxAttempts,
      initial: initial ?? this.initial,
      max: max ?? this.max,
      minDelay: minDelay ?? this.minDelay,
      multiplier: multiplier ?? this.multiplier,
      decorrelationFactor: decorrelationFactor ?? this.decorrelationFactor,
      strategy: strategy ?? this.strategy,
      honorRetryAfter: honorRetryAfter ?? this.honorRetryAfter,
      allowNonIdempotent: allowNonIdempotent ?? this.allowNonIdempotent,
      retryableCodes: retryableCodes ?? this.retryableCodes,
      isRetryable: isRetryable ?? this.isRetryable,
      jitterSource: jitterSource ?? this.jitterSource,
      sleep: sleep ?? this.sleep,
    );
  }
}

/// Cryptographically-secure uniform draw in `[0.0, 1.0)`. Uses
/// `Random.secure()`, which is backed by the platform CSPRNG
/// (`/dev/urandom`, `BCryptGenRandom`, or `Window.crypto.getRandomValues`).
/// Acceptable under FIPS 140-3 on platforms whose CSPRNG is validated.
double defaultJitterSource() => Random.secure().nextDouble();
