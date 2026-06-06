// Copyright 2026 The Pinguteca SDK Authors.
//
// Public entry point for the Layer 2 idempotency-key interceptor. Import as
// `package:sdk_core_dart/idempotency.dart`.

export 'src/idempotency/idempotency_key_interceptor.dart'
    show
        IdempotencyConfig,
        defaultIdempotencyKeyGenerator,
        idempotencyKeyHeader,
        idempotencyKeyInterceptor;
