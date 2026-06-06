// Copyright 2026 The Pinguteca SDK Authors.
//
// Public entry point for the Layer 2 auth interceptor. Import as
// `package:sdk_core_dart/auth.dart`.

export 'src/auth/auth_interceptor.dart'
    show AuthConfig, authInterceptor, authorizationHeader, bearerPrefix;
export 'src/auth/token_source.dart'
    show FunctionTokenSource, StaticTokenSource, TokenSource;
