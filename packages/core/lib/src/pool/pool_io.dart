// Copyright 2026 The Pinguteca SDK Authors.
//
// dart:io implementation of the pool helpers. Compiled on every non-web
// target (server, CLI, Flutter mobile/desktop). Web targets get the stub
// in pool_web.dart via conditional export.

import 'dart:io' as io;

import 'package:connectrpc/connect.dart' show HttpClient;
import 'package:connectrpc/io.dart' as connect_io;

import 'pool_config.dart';

/// Builds an [io.HttpClient] pre-configured for RPC traffic. Exposed so
/// tests and callers wanting both the raw client and the Connect-wrapped
/// form can apply [config] consistently.
io.HttpClient buildIoHttpClient([
  ConnectionPoolConfig config = const ConnectionPoolConfig(),
]) {
  final client = io.HttpClient();
  client.maxConnectionsPerHost = config.maxConnectionsPerHost;
  client.idleTimeout = config.idleTimeout;
  if (config.connectionTimeout != null) {
    client.connectionTimeout = config.connectionTimeout;
  }
  if (config.userAgent != null) {
    client.userAgent = config.userAgent;
  }
  return client;
}

/// Builds a Connect [HttpClient] backed by a pooled [io.HttpClient] over
/// HTTP/1.1. Use this when the transport is the Connect protocol over
/// plain HTTP; for gRPC or full-duplex streaming, prefer the HTTP/2
/// transport from `package:connectrpc/http2.dart`.
HttpClient pooledHttp1Client([
  ConnectionPoolConfig config = const ConnectionPoolConfig(),
]) {
  return connect_io.createHttpClient(buildIoHttpClient(config));
}
