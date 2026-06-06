// Copyright 2026 The Pinguteca SDK Authors.
//
// Web stub for the pool helpers. The browser owns connection pooling
// (HTTP/1.1, HTTP/2, HTTP/3 negotiated by the user agent) and exposes no
// API to tune it. Callers on web should build a [HttpClient] from
// `package:connectrpc/web.dart` directly and skip these helpers.

import 'package:connectrpc/connect.dart' show HttpClient;

import 'pool_config.dart';

/// Always throws on web. The browser pools internally; configure
/// connection behaviour via the user agent's settings if needed.
HttpClient pooledHttp1Client([
  ConnectionPoolConfig config = const ConnectionPoolConfig(),
]) {
  throw UnsupportedError(
    'pooledHttp1Client is unavailable on web. Browsers manage their own '
    'connection pool; build a Connect HttpClient from '
    'package:connectrpc/web.dart instead.',
  );
}
