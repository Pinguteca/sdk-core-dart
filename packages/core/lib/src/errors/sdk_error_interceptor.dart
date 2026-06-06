// Copyright 2026 The Pinguteca SDK Authors.
//
// Outermost Connect interceptor: converts any thrown ConnectException into
// an [SdkError] so callers can catch a single stable type without
// importing package:connectrpc.

import 'package:connectrpc/connect.dart';

import 'sdk_error.dart';

/// Builds an [Interceptor] that wraps every thrown [ConnectException] in an
/// [SdkError]. Place this OUTERMOST in the interceptor chain so it sees the
/// final error after retry, breaker, and every other interceptor have run:
///
/// ```
/// SdkError -> OTel -> Breaker -> Idempotency -> Retry -> Auth
/// ```
Interceptor sdkErrorInterceptor() {
  return <I extends Object, O extends Object>(AnyFn<I, O> next) {
    return (Request<I, O> req) async {
      try {
        return await next(req);
      } on SdkError {
        rethrow;
      } on ConnectException catch (error) {
        throw SdkError.fromConnectException(error);
      }
    };
  };
}
