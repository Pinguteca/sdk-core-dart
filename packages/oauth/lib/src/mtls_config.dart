// Copyright 2026 The Pinguteca SDK Authors.
//
// Cross-platform configuration for mutual TLS client authentication
// against an OAuth token endpoint (RFC 8705). Loading the certificate
// material requires dart:io; web targets get a stub via conditional
// export.

/// Configuration for [mtlsHttpClient].
final class MtlsConfig {
  /// Path to a PEM file containing the client certificate chain.
  final String certificateChainPath;

  /// Path to a PEM file containing the corresponding private key.
  final String privateKeyPath;

  /// Optional password for [privateKeyPath] when the key is encrypted.
  final String? privateKeyPassword;

  /// Optional path to a PEM file with extra trusted CA certificates.
  /// Use when the IdP's server certificate is issued by a private CA
  /// not in the platform trust store.
  final String? trustedCertificatesPath;

  /// Builds a config. All paths are read at the time
  /// [mtlsHttpClient] is invoked, not here.
  const MtlsConfig({
    required this.certificateChainPath,
    required this.privateKeyPath,
    this.privateKeyPassword,
    this.trustedCertificatesPath,
  });
}
