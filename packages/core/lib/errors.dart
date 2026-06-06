// Copyright 2026 The Pinguteca SDK Authors.
//
// Public entry point for the SDK's stable error type and boundary
// interceptor. Import as `package:sdk_core_dart/errors.dart`.

export 'src/errors/sdk_error.dart' show SdkError, SdkErrorCode, SdkErrorDetail;
export 'src/errors/sdk_error_interceptor.dart' show sdkErrorInterceptor;
