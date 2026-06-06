// Copyright 2026 The Pinguteca SDK Authors.
//
// Circuit breaker interceptor. Sits outside Retry per RFC 0002 so
// short-circuited calls never consume retry budget. Composition:
//
//   SdkError -> OTel -> Breaker -> Idempotency -> Retry -> Auth

import 'package:connectrpc/connect.dart';

import 'circuit_breaker.dart';

/// Builds an [Interceptor] that short-circuits calls grouped by procedure
/// (or by [CircuitBreakerConfig.keyFn]) when the upstream is failing.
///
/// Returned exceptions when the breaker is open carry
/// [Code.unavailable]; downstream interceptors (retry, SdkError) handle
/// them like any other unavailable response.
Interceptor circuitBreakerInterceptor([
  CircuitBreakerConfig config = const CircuitBreakerConfig(),
]) {
  final entries = <String, CircuitBreakerEntry>{};
  final isFailure = config.isFailure ?? defaultIsFailure;
  final keyFn = config.keyFn ?? _defaultKey;
  final now = config.now ?? DateTime.now;

  return <I extends Object, O extends Object>(AnyFn<I, O> next) {
    return (Request<I, O> req) async {
      final key = keyFn(req.spec.procedure);
      final entry = entries.putIfAbsent(key, CircuitBreakerEntry.new);

      _maybeRecoverToHalfOpen(entry, config, now);

      switch (entry.state) {
        case CircuitState.open:
          throw ConnectException(
            Code.unavailable,
            'circuit breaker open for $key',
          );
        case CircuitState.halfOpen:
          if (entry.trialInFlight) {
            throw ConnectException(
              Code.unavailable,
              'circuit breaker half-open trial already in flight for $key',
            );
          }
          entry.trialInFlight = true;
          try {
            final response = await next(req);
            _recordSuccess(entry, config);
            return response;
          } on ConnectException catch (error) {
            if (isFailure(error)) {
              _recordFailure(entry, config, now);
            }
            rethrow;
          } finally {
            entry.trialInFlight = false;
          }
        case CircuitState.closed:
          try {
            final response = await next(req);
            return response;
          } on ConnectException catch (error) {
            if (isFailure(error)) {
              _recordFailure(entry, config, now);
            }
            rethrow;
          }
      }
    };
  };
}

void _maybeRecoverToHalfOpen(
  CircuitBreakerEntry entry,
  CircuitBreakerConfig config,
  DateTime Function() now,
) {
  if (entry.state != CircuitState.open) return;
  final openedAt = entry.openedAt;
  if (openedAt == null) return;
  if (now().difference(openedAt) >= config.openTimeout) {
    entry.state = CircuitState.halfOpen;
    entry.halfOpenSuccesses = 0;
  }
}

void _recordFailure(
  CircuitBreakerEntry entry,
  CircuitBreakerConfig config,
  DateTime Function() now,
) {
  final t = now();
  final cutoff = t.subtract(config.window);
  entry.failures.removeWhere((f) => f.isBefore(cutoff));
  entry.failures.add(t);

  if (entry.state == CircuitState.halfOpen) {
    _trip(entry, t);
    return;
  }
  if (entry.failures.length >= config.failureThreshold) {
    _trip(entry, t);
  }
}

void _recordSuccess(CircuitBreakerEntry entry, CircuitBreakerConfig config) {
  if (entry.state != CircuitState.halfOpen) return;
  entry.halfOpenSuccesses++;
  if (entry.halfOpenSuccesses >= config.successThreshold) {
    entry.state = CircuitState.closed;
    entry.failures.clear();
    entry.openedAt = null;
    entry.halfOpenSuccesses = 0;
  }
}

void _trip(CircuitBreakerEntry entry, DateTime at) {
  entry.state = CircuitState.open;
  entry.openedAt = at;
  entry.halfOpenSuccesses = 0;
}

String _defaultKey(String procedure) => procedure;
