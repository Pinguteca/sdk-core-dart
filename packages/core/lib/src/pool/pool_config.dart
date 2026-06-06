// Copyright 2026 The Pinguteca SDK Authors.
//
// Cross-platform connection-pool tuning knobs. The actual pool lives in the
// underlying `dart:io` HttpClient (for HTTP/1.1) or the HTTP/2 transport's
// connection manager. Web targets ignore these values: the browser pools
// connections internally and exposes no API to tune them.

/// Defaults sized for RPC traffic: enough connections to absorb modest
/// concurrent fan-out without head-of-line blocking on HTTP/1.1, an idle
/// timeout long enough for typical interactive workloads, and a connection
/// timeout that gives slow networks a chance without stalling a UI thread.
final class ConnectionPoolConfig {
  /// Maximum number of concurrent connections kept open per origin host.
  /// HTTP/1.1 transports treat this as a hard ceiling; HTTP/2 transports
  /// usually need only one per host but accept the cap as an upper bound
  /// when multiplexing across many concurrent streams.
  final int maxConnectionsPerHost;

  /// How long an idle connection stays in the pool before the client
  /// closes it. Set to [Duration.zero] to disable keep-alive entirely
  /// (debugging only; defeats most of the pool's value).
  final Duration idleTimeout;

  /// How long the client waits for a TCP/TLS handshake before giving up.
  /// `null` defers to the OS default.
  final Duration? connectionTimeout;

  /// User-Agent header to send. Override when the upstream uses the
  /// header for traffic routing, A/B selection, or telemetry.
  final String? userAgent;

  /// Builds a config with the recommended RPC-shaped defaults.
  const ConnectionPoolConfig({
    this.maxConnectionsPerHost = 50,
    this.idleTimeout = const Duration(seconds: 90),
    this.connectionTimeout = const Duration(seconds: 10),
    this.userAgent,
  });
}
