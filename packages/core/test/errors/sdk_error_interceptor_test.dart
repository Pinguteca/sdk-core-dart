// Copyright 2026 The Pinguteca SDK Authors.

import 'dart:typed_data';

import 'package:connectrpc/connect.dart';
import 'package:sdk_core_dart/errors.dart';
import 'package:test/test.dart';

void main() {
  group('SdkError.fromConnectException', () {
    test('copies code, message, cause, details, and metadata', () {
      final cause = StateError('underlying');
      final detail = ErrorDetail(
        'type.googleapis.com/google.rpc.RetryInfo',
        Uint8List.fromList([0x0A, 0x02, 0x08, 0x05]),
      );
      final metadata = Headers()
        ..['x-request-id'] = 'req-7'
        ..add('x-tag', 'a')
        ..add('x-tag', 'b');
      final exception = ConnectException(
        Code.unavailable,
        'server is restarting',
        cause: cause,
        metadata: metadata,
        details: [detail],
      );

      final error = SdkError.fromConnectException(exception);

      expect(error.code, Code.unavailable);
      expect(error.message, 'server is restarting');
      expect(error.cause, same(cause));
      expect(error.details, hasLength(1));
      expect(error.details.single.type, detail.type);
      expect(error.details.single.value, detail.value);
      expect(error.metadata['x-request-id'], ['req-7']);
      expect(error.metadata['x-tag'], ['a', 'b']);
    });

    test('falls back to the exception itself as cause when none is set', () {
      final exception = ConnectException(Code.notFound, 'gone');

      final error = SdkError.fromConnectException(exception);

      expect(error.cause, same(exception));
    });
  });

  group('SdkError.local', () {
    test('captures caller-side failures', () {
      final error = SdkError.local(
        code: Code.invalidArgument,
        message: 'message must not be empty',
      );

      expect(error.code, Code.invalidArgument);
      expect(error.message, 'message must not be empty');
      expect(error.details, isEmpty);
      expect(error.metadata, isEmpty);
    });
  });

  group('sdkErrorInterceptor', () {
    test('passes a successful response through unchanged', () async {
      final wrapped = sdkErrorInterceptor()(_okStub(42));

      final response = await wrapped(_unaryReq());

      expect((response as UnaryResponse<int, int>).message, 42);
    });

    test('wraps thrown ConnectException as SdkError', () async {
      final wrapped = sdkErrorInterceptor()(
        _failStub(ConnectException(Code.unavailable, 'server is restarting')),
      );

      await expectLater(
        wrapped(_unaryReq()),
        throwsA(
          isA<SdkError>()
              .having((e) => e.code, 'code', Code.unavailable)
              .having((e) => e.message, 'message', 'server is restarting'),
        ),
      );
    });

    test('passes an existing SdkError through without re-wrapping', () async {
      final original = SdkError.local(
        code: Code.invalidArgument,
        message: 'bad input',
      );
      final wrapped = sdkErrorInterceptor()(_failStub(original));

      try {
        await wrapped(_unaryReq());
        fail('expected SdkError');
      } on SdkError catch (e) {
        expect(e, same(original));
      }
    });
  });
}

AnyFn<int, int> _okStub(int message) {
  return (Request<int, int> req) async {
    return UnaryResponse<int, int>(req.spec, Headers(), message, Headers());
  };
}

AnyFn<int, int> _failStub(Object error) {
  return (Request<int, int> req) async {
    throw error;
  };
}

UnaryRequest<int, int> _unaryReq() {
  return UnaryRequest<int, int>(
    Spec<int, int>(
      '/example.Service/Method',
      StreamType.unary,
      () => 0,
      () => 0,
    ),
    'https://example.invalid/svc/Method',
    Headers(),
    0,
    CancelableSignal(),
  );
}
