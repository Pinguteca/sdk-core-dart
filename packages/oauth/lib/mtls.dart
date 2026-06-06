// Copyright 2026 The Pinguteca SDK Authors.
//
// Public entry point for mTLS (RFC 8705) helpers. Import as
// `package:sdk_core_dart_oauth/mtls.dart`. The implementation is
// dart:io-only; web targets get a stub that throws UnsupportedError.

export 'src/mtls_config.dart' show MtlsConfig;
export 'src/mtls_io.dart'
    if (dart.library.html) 'src/mtls_web.dart'
    show mtlsHttpClient;
