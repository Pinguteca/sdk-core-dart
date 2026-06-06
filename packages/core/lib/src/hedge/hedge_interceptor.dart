// Copyright 2026 The Pinguteca SDK Authors.
//
// Hedged requests: for safe (NO_SIDE_EFFECTS) RPCs, send a small number of
// duplicate calls spaced by a configurable delay and return the first
// successful response. Loser requests are cancelled via their AbortSignal
// so the server can stop work.
//
// Composition order per RFC 0002: hedge sits OUTSIDE the idempotency-key
// interceptor so each hedge attempt gets its own key (the server can
// tell duplicates apart for analytics) but INSIDE retry so retries are
// applied to the surviving attempt only.

import 'dart:async';

import 'package:connectrpc/connect.dart';

/// Tuning knobs for [hedgeInterceptor].
final class HedgeConfig {
  /// How many EXTRA requests to send beyond the primary. Total in-flight
  /// at peak is `1 + hedgeCount`. Default 1 (one hedge), the value almost
  /// every published study finds best for p99 latency without doubling
  /// upstream load.
  final int hedgeCount;

  /// Delay between launching each duplicate. The first hedge fires
  /// `hedgeDelay` after the primary, the second `hedgeDelay * 2`, etc.
  /// Picking a value around the upstream's p50 latency wastes the
  /// fewest hedges while still trimming the tail.
  final Duration hedgeDelay;

  /// Predicate deciding whether a request is hedgeable. Defaults to
  /// "only NO_SIDE_EFFECTS unary": safe to repeat because the schema
  /// promises no side effects. Flip on for IDEMPOTENT calls only when
  /// the server deduplicates by idempotency key, or for a custom
  /// per-method allowlist.
  final bool Function<I extends Object, O extends Object>(Request<I, O>)?
  isEligible;

  /// Builds a config with the recommended defaults.
  const HedgeConfig({
    this.hedgeCount = 1,
    this.hedgeDelay = const Duration(milliseconds: 50),
    this.isEligible,
  });
}

/// Builds an [Interceptor] that hedges safe unary RPCs.
///
/// Behaviour:
/// - Streaming requests pass through unchanged.
/// - Ineligible requests pass through unchanged (default: only
///   `Idempotency.noSideEffects` unary calls hedge).
/// - Up to `hedgeCount` duplicate attempts are spawned, each in a
///   CancelableSignal scoped to the call. The first attempt to succeed
///   completes the call and cancels every loser.
/// - If every attempt fails, the most recent error is thrown.
Interceptor hedgeInterceptor([HedgeConfig config = const HedgeConfig()]) {
  if (config.hedgeCount < 1) {
    throw ArgumentError.value(
      config.hedgeCount,
      'hedgeCount',
      'must be at least 1',
    );
  }
  if (config.hedgeDelay <= Duration.zero) {
    throw ArgumentError.value(
      config.hedgeDelay,
      'hedgeDelay',
      'must be a positive duration',
    );
  }

  final eligible = config.isEligible ?? _defaultIsEligible;

  return <I extends Object, O extends Object>(AnyFn<I, O> next) {
    return (Request<I, O> req) async {
      if (req.spec.streamType != StreamType.unary || !eligible<I, O>(req)) {
        return next(req);
      }
      return _race<I, O>(req, next, config);
    };
  };
}

bool _defaultIsEligible<I extends Object, O extends Object>(Request<I, O> req) {
  return req.spec.idempotency == Idempotency.noSideEffects;
}

Future<Response<I, O>> _race<I extends Object, O extends Object>(
  Request<I, O> req,
  AnyFn<I, O> next,
  HedgeConfig config,
) {
  final completer = Completer<Response<I, O>>();
  final signals = <CancelableSignal>[];
  final pendingErrors = <Object>[];
  final total = 1 + config.hedgeCount;
  var completed = 0;

  void launch(int index) {
    if (completer.isCompleted) return;
    final signal = CancelableSignal(parent: req.signal);
    signals.add(signal);
    final childReq = _withSignal<I, O>(req, signal);
    next(childReq).then(
      (response) {
        if (completer.isCompleted) return;
        completer.complete(response);
        // Cancel every sibling that has not finished yet.
        for (final s in signals) {
          if (!identical(s, signal)) {
            s.cancel('hedge winner selected');
          }
        }
      },
      onError: (Object error, StackTrace stack) {
        completed++;
        pendingErrors.add(error);
        if (completed == total && !completer.isCompleted) {
          completer.completeError(pendingErrors.last, stack);
        }
      },
    );
  }

  // Primary request fires immediately.
  launch(0);

  // Schedule each hedge. Cancel the timer chain if the call has already
  // completed by then.
  for (var i = 1; i <= config.hedgeCount; i++) {
    Future.delayed(config.hedgeDelay * i, () {
      if (!completer.isCompleted) {
        launch(i);
      }
    });
  }

  return completer.future;
}

Request<I, O> _withSignal<I extends Object, O extends Object>(
  Request<I, O> req,
  AbortSignal signal,
) {
  return switch (req) {
    UnaryRequest<I, O>() => UnaryRequest<I, O>(
      req.spec,
      req.url,
      req.headers,
      req.message,
      signal,
    ),
    StreamRequest<I, O>() => StreamRequest<I, O>(
      req.spec,
      req.url,
      req.headers,
      req.message,
      signal,
    ),
  };
}
