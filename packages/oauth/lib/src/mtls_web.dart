// Copyright 2026 The Pinguteca SDK Authors.
//
// Web stub for the mTLS helper. The browser owns TLS; consumer code
// cannot present a client certificate from JavaScript.

import 'package:http/http.dart' as http;

import 'mtls_config.dart';

/// Always throws on web: browsers do not expose a client-cert API.
/// mTLS auth for the OAuth token endpoint must run from a native or
/// server-side process.
http.Client mtlsHttpClient(MtlsConfig config) {
  throw UnsupportedError(
    'mtlsHttpClient is unavailable on web; browsers do not expose a '
    'client-cert API. Run the OAuth client_credentials or '
    'authorization_code flow from a native or server-side process.',
  );
}
