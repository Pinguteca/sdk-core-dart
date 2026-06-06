// Copyright 2026 The Pinguteca SDK Authors.
//
// TokenSource is the abstraction the auth interceptor calls before every
// request that needs an Authorization header. Implementations decide whether
// the token is static, fetched per-call, cached, or refreshed from an OAuth
// 2.0 endpoint.
//
// The SDK ships two concrete sources (static, function-backed) and the
// interface for callers writing their own. A full OAuth lifecycle helper
// (client_credentials, authorization_code) belongs in a Layer 3 companion
// package rather than the zero-3P core.

/// Source of credentials for the auth interceptor. Called once per request
/// that does not already carry an Authorization header.
abstract interface class TokenSource {
  /// Returns the token to send. May be sync via `Future.value(...)` or
  /// genuinely async when the implementation refreshes against an IdP.
  Future<String> token();
}

/// Returns the same token for every call. Use for API keys, manually-issued
/// long-lived JWTs, and tests.
final class StaticTokenSource implements TokenSource {
  /// Builds a source that always returns [value].
  StaticTokenSource(this._value);

  final String _value;

  @override
  Future<String> token() => Future.value(_value);
}

/// Adapts a function into a [TokenSource]. The function is invoked once per
/// request that needs a token. Callers responsible for caching and refresh
/// implement that logic inside the closure.
final class FunctionTokenSource implements TokenSource {
  /// Builds a source that delegates each [token] call to [fetch].
  FunctionTokenSource(this._fetch);

  final Future<String> Function() _fetch;

  @override
  Future<String> token() => _fetch();
}
