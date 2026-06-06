// Copyright 2026 The Pinguteca SDK Authors.
//
// dart:io implementation of the mTLS helper. Builds an http.Client whose
// underlying io.HttpClient presents the configured client certificate
// during the TLS handshake. Used by the OAuth grant flows when
// ClientAuthMode.mtls is selected (RFC 8705).

import 'dart:io' as io;

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'mtls_config.dart';

/// Builds an [http.Client] that presents the certificate from [config]
/// during the TLS handshake. The token endpoint identifies the client
/// from the cert; no HTTP-layer credentials are sent.
///
/// Both PEM files (certificate chain and private key) are loaded
/// synchronously here. Errors from `SecurityContext` (invalid PEM, key
/// password mismatch, missing files) propagate to the caller.
http.Client mtlsHttpClient(MtlsConfig config) {
  final context = io.SecurityContext(withTrustedRoots: true);
  context.useCertificateChain(config.certificateChainPath);
  context.usePrivateKey(
    config.privateKeyPath,
    password: config.privateKeyPassword,
  );
  if (config.trustedCertificatesPath != null) {
    context.setTrustedCertificates(config.trustedCertificatesPath!);
  }
  final httpClient = io.HttpClient(context: context);
  return IOClient(httpClient);
}
