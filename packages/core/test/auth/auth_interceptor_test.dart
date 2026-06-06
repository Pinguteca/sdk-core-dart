// Copyright 2026 The Pinguteca SDK Authors.

import 'package:connectrpc/connect.dart';
import 'package:sdk_core_dart/auth.dart';
import 'package:test/test.dart';

void main() {
  group('authInterceptor', () {
    test(
      'sets Authorization with Bearer prefix from a static source',
      () async {
        final captor = _AuthCaptor();
        final wrapped = authInterceptor(
          AuthConfig(source: StaticTokenSource('abc.def.ghi')),
        )(captor.next);

        await wrapped(_unaryReq());

        expect(captor.lastValue, 'Bearer abc.def.ghi');
      },
    );

    test('calls the function-backed source on every request', () async {
      var calls = 0;
      final wrapped = authInterceptor(
        AuthConfig(
          source: FunctionTokenSource(() async {
            calls++;
            return 'tok-$calls';
          }),
        ),
      )(_HeaderCaptor().next);

      await wrapped(_unaryReq());
      await wrapped(_unaryReq());
      await wrapped(_unaryReq());

      expect(calls, 3);
    });

    test('does not overwrite a caller-supplied header by default', () async {
      final captor = _AuthCaptor();
      final wrapped = authInterceptor(
        AuthConfig(source: StaticTokenSource('generated')),
      )(captor.next);
      final headers = Headers()..[authorizationHeader] = 'Bearer caller';

      await wrapped(_unaryReq(headers: headers));

      expect(captor.lastValue, 'Bearer caller');
    });

    test('overrides the caller header when overrideExisting is true', () async {
      final captor = _AuthCaptor();
      final wrapped = authInterceptor(
        AuthConfig(
          source: StaticTokenSource('generated'),
          overrideExisting: true,
        ),
      )(captor.next);
      final headers = Headers()..[authorizationHeader] = 'Bearer caller';

      await wrapped(_unaryReq(headers: headers));

      expect(captor.lastValue, 'Bearer generated');
    });

    test(
      'supports a raw API-key header via empty prefix and custom name',
      () async {
        final captor = _AuthCaptor(header: 'x-api-key');
        final wrapped = authInterceptor(
          AuthConfig(
            source: StaticTokenSource('key-42'),
            headerName: 'x-api-key',
            prefix: '',
          ),
        )(captor.next);

        await wrapped(_unaryReq());

        expect(captor.lastValue, 'key-42');
      },
    );

    test('applies to streaming requests too', () async {
      final captor = _AuthCaptor();
      final wrapped = authInterceptor(
        AuthConfig(source: StaticTokenSource('streaming-token')),
      )(captor.next);
      final req = StreamRequest<int, int>(
        Spec<int, int>(
          '/example.Service/Stream',
          StreamType.bidi,
          () => 0,
          () => 0,
        ),
        'https://example.invalid/svc/Stream',
        Headers(),
        const Stream<int>.empty(),
        CancelableSignal(),
      );

      await wrapped(req);

      expect(captor.lastValue, 'Bearer streaming-token');
    });

    test('propagates an async TokenSource error', () async {
      final wrapped = authInterceptor(
        AuthConfig(
          source: FunctionTokenSource(
            () => Future.error(StateError('refresh failed')),
          ),
        ),
      )(_HeaderCaptor().next);

      expect(() => wrapped(_unaryReq()), throwsA(isA<StateError>()));
    });
  });
}

class _AuthCaptor {
  _AuthCaptor({this.header = authorizationHeader});

  final String header;
  String? lastValue;

  Future<Response<int, int>> next(Request<int, int> req) async {
    lastValue = req.headers[header];
    return UnaryResponse<int, int>(req.spec, Headers(), 0, Headers());
  }
}

class _HeaderCaptor {
  Future<Response<int, int>> next(Request<int, int> req) async {
    return UnaryResponse<int, int>(req.spec, Headers(), 0, Headers());
  }
}

UnaryRequest<int, int> _unaryReq({Headers? headers}) {
  return UnaryRequest<int, int>(
    Spec<int, int>(
      '/example.Service/Method',
      StreamType.unary,
      () => 0,
      () => 0,
      idempotency: Idempotency.idempotent,
    ),
    'https://example.invalid/svc/Method',
    headers ?? Headers(),
    0,
    CancelableSignal(),
  );
}
