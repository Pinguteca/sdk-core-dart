// Copyright 2026 The Pinguteca SDK Authors.
//
// Public entry point for the Layer 2 circuit breaker. Import as
// `package:sdk_core_dart/breaker.dart`.

export 'src/breaker/circuit_breaker.dart'
    show
        CircuitBreakerConfig,
        CircuitBreakerEntry,
        CircuitState,
        defaultIsFailure;
export 'src/breaker/circuit_breaker_interceptor.dart'
    show circuitBreakerInterceptor;
