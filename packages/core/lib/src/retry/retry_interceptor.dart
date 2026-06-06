// Copyright 2026 The Pinguteca SDK Authors.
//
// Connect interceptor implementing exponential backoff with jitter and
// respect for server-provided retry hints. Streaming RPCs are passed through
// untouched: a stream cannot be replayed safely.
//
// The user-visible contract (algorithm, defaults, retryable code set,
// server-hint precedence, idempotency safety gate, composition order) is
// pinned in sdk-scaffold/docs/rfc/0006-retry-behavioural-contract.md.

import 'dart:async';
import 'dart:math' as math;

import 'package:connectrpc/connect.dart';

import 'retry_after.dart';
import 'retry_config.dart';

/// Builds a Connect [Interceptor] that retries failed unary calls per
/// [RetryConfig]. Without arguments, uses RFC 0006 defaults.
///
/// Composition order, outermost to innermost (per RFC 0002):
/// `OTel -> Breaker -> Idempotency -> Retry -> Auth`.
Interceptor retryInterceptor([RetryConfig config = const RetryConfig()]) {
  final jitter = config.jitterSource ?? defaultJitterSource;
  final sleep = config.sleep ?? _realSleep;
  final maxAttempts = math.max(2, config.maxAttempts);
  final initial = config.initial.inMicroseconds <= 0
      ? const Duration(milliseconds: 100)
      : config.initial;
  final maxDelay = config.max.inMicroseconds < initial.inMicroseconds
      ? initial
      : config.max;
  final multiplier = math.max(1.0, config.multiplier);
  final decorrelation = config.decorrelationFactor < 1.0
      ? 3.0
      : config.decorrelationFactor;

  return <I extends Object, O extends Object>(AnyFn<I, O> next) {
    return (Request<I, O> req) async {
      // Streaming is never retried: replaying a stream of inputs is not safe.
      if (req.spec.streamType != StreamType.unary) {
        return next(req);
      }
      // Idempotency gate: methods the schema does not annotate are skipped
      // unless the caller explicitly opts in.
      if (!config.allowNonIdempotent && req.spec.idempotency == null) {
        return next(req);
      }

      var ceiling = initial;
      var prev = initial;
      var attempt = 0;
      while (true) {
        attempt++;
        try {
          return await next(req);
        } on ConnectException catch (error) {
          final isLast = attempt >= maxAttempts;
          if (isLast || !_shouldRetry(error, config)) {
            rethrow;
          }
          final delay = _nextDelay(
            error: error,
            ceiling: ceiling,
            prev: prev,
            config: config,
            maxDelay: maxDelay,
            initial: initial,
            decorrelation: decorrelation,
            jitter: jitter,
          );
          await sleep(delay);
          prev = delay;
          ceiling = _grow(ceiling, multiplier, maxDelay);
        }
      }
    };
  };
}

bool _shouldRetry(ConnectException error, RetryConfig config) {
  if (config.isRetryable != null) {
    return config.isRetryable!(error);
  }
  return config.retryableCodes.contains(error.code);
}

Duration _nextDelay({
  required ConnectException error,
  required Duration ceiling,
  required Duration prev,
  required RetryConfig config,
  required Duration maxDelay,
  required Duration initial,
  required double decorrelation,
  required double Function() jitter,
}) {
  if (config.honorRetryAfter) {
    final hint = retryHintFrom(error);
    if (hint != null && hint > Duration.zero) {
      return hint;
    }
  }
  switch (config.strategy) {
    case RetryStrategy.full:
      return _fullDelay(ceiling, maxDelay, config.minDelay, jitter);
    case RetryStrategy.decorrelated:
      return _decorrelatedDelay(prev, initial, maxDelay, decorrelation, jitter);
  }
}

Duration _fullDelay(
  Duration ceiling,
  Duration maxDelay,
  Duration minDelay,
  double Function() jitter,
) {
  final upperMicros = math.min(ceiling.inMicroseconds, maxDelay.inMicroseconds);
  if (upperMicros <= 0) {
    return Duration.zero;
  }
  if (minDelay > Duration.zero) {
    if (upperMicros <= minDelay.inMicroseconds) {
      return minDelay;
    }
    final spread = (upperMicros - minDelay.inMicroseconds).toDouble();
    return minDelay + Duration(microseconds: (jitter() * spread).toInt());
  }
  return Duration(microseconds: (jitter() * upperMicros).toInt());
}

Duration _decorrelatedDelay(
  Duration prev,
  Duration initial,
  Duration maxDelay,
  double decorrelation,
  double Function() jitter,
) {
  final scaledMicros = (prev.inMicroseconds.toDouble() * decorrelation).toInt();
  final upperMicros = math.min(scaledMicros, maxDelay.inMicroseconds);
  if (upperMicros <= initial.inMicroseconds) {
    return initial;
  }
  final spread = (upperMicros - initial.inMicroseconds).toDouble();
  return initial + Duration(microseconds: (jitter() * spread).toInt());
}

Duration _grow(Duration ceiling, double multiplier, Duration maxDelay) {
  final grownMicros = (ceiling.inMicroseconds.toDouble() * multiplier).toInt();
  return Duration(microseconds: math.min(grownMicros, maxDelay.inMicroseconds));
}

Future<void> _realSleep(Duration delay) =>
    delay <= Duration.zero ? Future.value() : Future.delayed(delay);
