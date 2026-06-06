// Copyright 2026 The Pinguteca SDK Authors.
//
// Per-key circuit breaker state machine. Tracked separately from the
// interceptor so callers building custom interceptors (e.g. a
// per-method-class breaker) can reuse the same state semantics.

import 'package:connectrpc/connect.dart';

/// Breaker lifecycle.
///
/// - [closed]: requests pass through; failures accumulate. When the count
///   inside [CircuitBreakerConfig.window] reaches
///   [CircuitBreakerConfig.failureThreshold] the breaker opens.
/// - [open]: requests short-circuit with a synthetic
///   `Code.unavailable` exception until [CircuitBreakerConfig.openTimeout]
///   elapses; then the breaker transitions to [halfOpen].
/// - [halfOpen]: a single trial request is allowed through. Success
///   transitions back to [closed]; failure re-opens the breaker.
enum CircuitState {
  /// Requests pass through normally; failures accumulate in the window.
  closed,

  /// Requests short-circuit until the open timeout elapses.
  open,

  /// A trial request is allowed through to probe upstream recovery.
  halfOpen,
}

/// Default predicate for "is this exception a breaker failure". Mirrors the
/// retry interceptor's default retryable set so the breaker reacts to the
/// same transient codes retry budgets are spent on.
bool defaultIsFailure(ConnectException error) {
  switch (error.code) {
    case Code.unavailable:
    case Code.resourceExhausted:
    case Code.aborted:
    case Code.deadlineExceeded:
    case Code.internal:
    case Code.dataLoss:
      return true;
    default:
      return false;
  }
}

/// Tuning knobs for the breaker.
final class CircuitBreakerConfig {
  /// Consecutive (within [window]) failures that flip closed -> open.
  final int failureThreshold;

  /// Successful trial calls in half-open needed to flip back to closed.
  /// Practical values are 1-3; raising it costs latency on recovery.
  final int successThreshold;

  /// Rolling window for counting failures. Older failures fall off.
  final Duration window;

  /// Time the breaker stays open before allowing a half-open trial.
  final Duration openTimeout;

  /// Predicate for "did this exception fail the upstream". Defaults to
  /// [defaultIsFailure].
  final bool Function(ConnectException error)? isFailure;

  /// Grouping function: maps a procedure path to a breaker bucket. The
  /// default keys by the procedure path verbatim so each method has its
  /// own breaker; override to key by host or service to share state
  /// across methods.
  final String Function(String procedure)? keyFn;

  /// Clock source. Tests inject a controllable clock.
  final DateTime Function()? now;

  /// Builds a config with the recommended defaults.
  const CircuitBreakerConfig({
    this.failureThreshold = 5,
    this.successThreshold = 1,
    this.window = const Duration(seconds: 10),
    this.openTimeout = const Duration(seconds: 30),
    this.isFailure,
    this.keyFn,
    this.now,
  });
}

/// Sliding-window state for a single breaker bucket. Mutable, accessed by
/// the interceptor across many async invocations; safe because Dart's
/// single-threaded isolate guarantees no concurrent mutation.
final class CircuitBreakerEntry {
  /// Current state. Reads should always observe the latest write.
  CircuitState state = CircuitState.closed;

  /// Timestamps of failures within [CircuitBreakerConfig.window]. Trimmed
  /// on every record.
  final List<DateTime> failures = <DateTime>[];

  /// When the breaker transitioned to [CircuitState.open]. Used to decide
  /// when to move to [CircuitState.halfOpen].
  DateTime? openedAt;

  /// Consecutive successes observed while in [CircuitState.halfOpen].
  int halfOpenSuccesses = 0;

  /// True when a half-open trial is currently in flight; gates concurrent
  /// trials so only one probe is sent per recovery window.
  bool trialInFlight = false;
}
