// Copyright 2026 The Pinguteca SDK Authors.
//
// Connect interceptor that attaches credentials to every outgoing request
// via a [TokenSource]. Composes innermost per RFC 0002 so a token refreshed
// between retry attempts is fetched fresh on each next() call.

import 'package:connectrpc/connect.dart';

import 'token_source.dart';

/// Conventional header for Bearer / API-key credentials.
const authorizationHeader = 'authorization';

/// Conventional Bearer prefix per RFC 6750.
const bearerPrefix = 'Bearer ';

/// Tuning knobs for [authInterceptor].
final class AuthConfig {
  /// Where the credential lands. Override to `x-api-key` (with `prefix: ''`)
  /// for vendor API-key conventions.
  final String headerName;

  /// String prepended to the token. Defaults to RFC 6750 `Bearer `. Set to
  /// the empty string for raw API-key headers.
  final String prefix;

  /// Source of the credential value.
  final TokenSource source;

  /// When true, overwrite a caller-supplied header. Default false: explicit
  /// caller intent wins (useful for per-call credential overrides).
  final bool overrideExisting;

  /// Builds a config that injects `authorization: Bearer <token>` from
  /// [source].
  const AuthConfig({
    required this.source,
    this.headerName = authorizationHeader,
    this.prefix = bearerPrefix,
    this.overrideExisting = false,
  });
}

/// Builds an [Interceptor] that fetches a credential from [AuthConfig.source]
/// and writes it into [AuthConfig.headerName] before delegating to `next`.
///
/// Composition order per RFC 0002: auth sits innermost so each retry attempt
/// re-runs through this interceptor and a refreshed token is acquired before
/// the next network call.
Interceptor authInterceptor(AuthConfig config) {
  return <I extends Object, O extends Object>(AnyFn<I, O> next) {
    return (Request<I, O> req) async {
      if (!config.overrideExisting && req.headers[config.headerName] != null) {
        return next(req);
      }
      final token = await config.source.token();
      req.headers[config.headerName] = '${config.prefix}$token';
      return next(req);
    };
  };
}
