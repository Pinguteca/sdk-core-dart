// Copyright 2026 The Pinguteca SDK Authors.
//
// Connect interceptor that enforces a per-call deadline. The wrapped
// [AbortSignal] fires after the timeout elapses; the Connect-Dart transports
// (Connect, gRPC, gRPC-Web) auto-derive `Connect-Timeout-Ms` / `grpc-timeout`
// headers from `signal.deadline`, so this interceptor propagates the deadline
// to the wire without manually touching headers.

import 'package:connectrpc/connect.dart';

/// Builds an [Interceptor] that applies [timeout] to every call.
///
/// The interceptor composes with any deadline already carried by the parent
/// [AbortSignal]: if the parent's deadline is tighter than `now + timeout`,
/// the parent wins and no wrapping happens. Otherwise a [TimeoutSignal] is
/// installed on a copy of the request.
///
/// Composition order per RFC 0002: timeout sits outside retry, so the
/// deadline covers all retry attempts, not each individual attempt.
Interceptor timeoutInterceptor(Duration timeout) {
  if (timeout <= Duration.zero) {
    throw ArgumentError.value(
      timeout,
      'timeout',
      'must be a positive duration',
    );
  }

  return <I extends Object, O extends Object>(AnyFn<I, O> next) {
    return (Request<I, O> req) {
      final parentDeadline = req.signal.deadline;
      final candidate = DateTime.now().add(timeout);
      if (parentDeadline != null && !candidate.isBefore(parentDeadline)) {
        return next(req);
      }
      final signal = TimeoutSignal(timeout, parent: req.signal);
      return next(_withSignal(req, signal));
    };
  };
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
