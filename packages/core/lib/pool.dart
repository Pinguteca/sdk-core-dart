// Copyright 2026 The Pinguteca SDK Authors.
//
// Public entry point for the Layer 2 connection-pool helpers. Import as
// `package:sdk_core_dart/pool.dart`.
//
// dart:io targets get the real implementation; web targets get a stub
// that throws UnsupportedError because the browser owns pooling.

export 'src/pool/pool_config.dart' show ConnectionPoolConfig;
export 'src/pool/pool_io.dart'
    if (dart.library.html) 'src/pool/pool_web.dart'
    show pooledHttp1Client;
