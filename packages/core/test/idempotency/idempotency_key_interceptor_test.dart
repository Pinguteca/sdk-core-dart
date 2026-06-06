// Copyright 2026 The Pinguteca SDK Authors.

import 'package:connectrpc/connect.dart';
import 'package:sdk_core_dart/idempotency.dart';
import 'package:test/test.dart';

void main() {
  group('idempotencyKeyInterceptor', () {
    test('injects a header on IDEMPOTENT unary calls', () async {
      final captor = _HeaderCaptor();
      final wrapped = idempotencyKeyInterceptor(
        IdempotencyConfig(keyGenerator: () => 'fixed-key'),
      )(captor.next);

      await wrapped(_unaryReq(idempotency: Idempotency.idempotent));

      expect(captor.lastKey, 'fixed-key');
    });

    test(
      'does not inject on methods without an idempotency annotation',
      () async {
        final captor = _HeaderCaptor();
        final wrapped = idempotencyKeyInterceptor(
          IdempotencyConfig(keyGenerator: () => 'fixed-key'),
        )(captor.next);

        await wrapped(_unaryReq(idempotency: null));

        expect(captor.lastKey, isNull);
      },
    );

    test('skips NO_SIDE_EFFECTS by default', () async {
      final captor = _HeaderCaptor();
      final wrapped = idempotencyKeyInterceptor(
        IdempotencyConfig(keyGenerator: () => 'fixed-key'),
      )(captor.next);

      await wrapped(_unaryReq(idempotency: Idempotency.noSideEffects));

      expect(captor.lastKey, isNull);
    });

    test('includes NO_SIDE_EFFECTS when configured', () async {
      final captor = _HeaderCaptor();
      final wrapped = idempotencyKeyInterceptor(
        IdempotencyConfig(
          keyGenerator: () => 'fixed-key',
          includeNoSideEffects: true,
        ),
      )(captor.next);

      await wrapped(_unaryReq(idempotency: Idempotency.noSideEffects));

      expect(captor.lastKey, 'fixed-key');
    });

    test('does not overwrite a caller-supplied header', () async {
      final captor = _HeaderCaptor();
      final wrapped = idempotencyKeyInterceptor(
        IdempotencyConfig(keyGenerator: () => 'generated'),
      )(captor.next);
      final headers = Headers()..[idempotencyKeyHeader] = 'caller-supplied';

      await wrapped(
        _unaryReq(idempotency: Idempotency.idempotent, headers: headers),
      );

      expect(captor.lastKey, 'caller-supplied');
    });

    test('streaming requests pass through untouched', () async {
      final captor = _HeaderCaptor();
      final wrapped = idempotencyKeyInterceptor(
        IdempotencyConfig(keyGenerator: () => 'fixed-key'),
      )(captor.next);
      final req = StreamRequest<int, int>(
        Spec<int, int>(
          '/example.Service/Stream',
          StreamType.bidi,
          () => 0,
          () => 0,
          idempotency: Idempotency.idempotent,
        ),
        'https://example.invalid/svc/Stream',
        Headers(),
        const Stream<int>.empty(),
        CancelableSignal(),
      );

      await wrapped(req);

      expect(req.headers[idempotencyKeyHeader], isNull);
    });

    test('generates a fresh key per request', () async {
      final keys = <String>[];
      final wrapped = idempotencyKeyInterceptor()(_streamingCapture(keys));

      await wrapped(_unaryReq(idempotency: Idempotency.idempotent));
      await wrapped(_unaryReq(idempotency: Idempotency.idempotent));
      await wrapped(_unaryReq(idempotency: Idempotency.idempotent));

      expect(keys, hasLength(3));
      expect(keys.toSet(), hasLength(3));
      for (final k in keys) {
        expect(k, matches(r'^[0-9a-f]{32}$'));
      }
    });

    test('honours a custom header name', () async {
      final captor = _HeaderCaptor(header: 'x-idempotency-key');
      final wrapped = idempotencyKeyInterceptor(
        IdempotencyConfig(
          headerName: 'x-idempotency-key',
          keyGenerator: () => 'fixed-key',
        ),
      )(captor.next);

      await wrapped(_unaryReq(idempotency: Idempotency.idempotent));

      expect(captor.lastKey, 'fixed-key');
    });
  });

  group('defaultIdempotencyKeyGenerator', () {
    test('emits 128-bit lowercase hex', () {
      final key = defaultIdempotencyKeyGenerator();
      expect(key, matches(r'^[0-9a-f]{32}$'));
    });

    test('produces distinct values across calls', () {
      final samples = List.generate(8, (_) => defaultIdempotencyKeyGenerator());
      expect(samples.toSet().length, samples.length);
    });
  });
}

class _HeaderCaptor {
  _HeaderCaptor({this.header = idempotencyKeyHeader});

  final String header;
  String? lastKey;

  Future<Response<int, int>> next(Request<int, int> req) async {
    lastKey = req.headers[header];
    return UnaryResponse<int, int>(req.spec, Headers(), 0, Headers());
  }
}

AnyFn<int, int> _streamingCapture(List<String> keys) {
  return (Request<int, int> req) async {
    final key = req.headers[idempotencyKeyHeader];
    if (key != null) keys.add(key);
    return UnaryResponse<int, int>(req.spec, Headers(), 0, Headers());
  };
}

UnaryRequest<int, int> _unaryReq({
  required Idempotency? idempotency,
  Headers? headers,
}) {
  return UnaryRequest<int, int>(
    Spec<int, int>(
      '/example.Service/Method',
      StreamType.unary,
      () => 0,
      () => 0,
      idempotency: idempotency,
    ),
    'https://example.invalid/svc/Method',
    headers ?? Headers(),
    0,
    CancelableSignal(),
  );
}
