// Copyright 2026 The Pinguteca SDK Authors.

import 'package:connectrpc/connect.dart';
import 'package:sdk_core_dart/timeout.dart';
import 'package:test/test.dart';

void main() {
  group('timeoutInterceptor', () {
    test('rejects non-positive durations', () {
      expect(() => timeoutInterceptor(Duration.zero), throwsArgumentError);
      expect(
        () => timeoutInterceptor(const Duration(milliseconds: -1)),
        throwsArgumentError,
      );
    });

    test(
      'wraps the request signal with a deadline derived from timeout',
      () async {
        final captor = _RequestCaptor();
        final wrapped = timeoutInterceptor(const Duration(seconds: 5))(
          captor.next,
        );

        final before = DateTime.now();
        await wrapped(_unaryReq(signal: CancelableSignal()));
        final after = DateTime.now();

        final deadline = captor.last!.signal.deadline;
        expect(deadline, isNotNull);
        final earliestExpected = before.add(const Duration(seconds: 5));
        final latestExpected = after.add(const Duration(seconds: 5));
        expect(deadline!.isBefore(earliestExpected), isFalse);
        expect(deadline.isAfter(latestExpected), isFalse);
      },
    );

    test('keeps the parent deadline when it is tighter', () async {
      final captor = _RequestCaptor();
      final wrapped = timeoutInterceptor(const Duration(seconds: 60))(
        captor.next,
      );
      final tightParent = DeadlineSignal(
        DateTime.now().add(const Duration(seconds: 1)),
      );

      await wrapped(_unaryReq(signal: tightParent));

      // The pass-through path does not rebuild the request, so the captured
      // signal is the parent itself.
      expect(captor.last!.signal, same(tightParent));
    });

    test('overrides a looser parent deadline', () async {
      final captor = _RequestCaptor();
      final wrapped = timeoutInterceptor(const Duration(seconds: 1))(
        captor.next,
      );
      final looseParent = DeadlineSignal(
        DateTime.now().add(const Duration(seconds: 60)),
      );

      final before = DateTime.now();
      await wrapped(_unaryReq(signal: looseParent));
      final after = DateTime.now();

      final deadline = captor.last!.signal.deadline;
      expect(deadline, isNotNull);
      expect(
        deadline!.isBefore(before.add(const Duration(seconds: 1))),
        isFalse,
      );
      expect(deadline.isAfter(after.add(const Duration(seconds: 1))), isFalse);
    });

    test(
      'preserves spec, url, headers, and message on the new request',
      () async {
        final captor = _RequestCaptor();
        final wrapped = timeoutInterceptor(const Duration(seconds: 5))(
          captor.next,
        );
        final headers = Headers()..['x-tenant'] = 't-9';
        final req = UnaryRequest<int, int>(
          _spec(),
          'https://example.invalid/svc/Method',
          headers,
          42,
          CancelableSignal(),
        );

        await wrapped(req);

        final captured = captor.last! as UnaryRequest<int, int>;
        expect(captured.spec, same(req.spec));
        expect(captured.url, req.url);
        expect(captured.headers['x-tenant'], 't-9');
        expect(captured.message, 42);
      },
    );

    test('wraps streaming requests too', () async {
      final captor = _RequestCaptor();
      final wrapped = timeoutInterceptor(const Duration(seconds: 5))(
        captor.next,
      );
      final req = StreamRequest<int, int>(
        Spec<int, int>(
          '/example.Service/StreamMethod',
          StreamType.bidi,
          () => 0,
          () => 0,
          idempotency: Idempotency.idempotent,
        ),
        'https://example.invalid/svc/StreamMethod',
        Headers(),
        const Stream<int>.empty(),
        CancelableSignal(),
      );

      await wrapped(req);

      expect(captor.last, isA<StreamRequest<int, int>>());
      expect(captor.last!.signal.deadline, isNotNull);
    });

    test('cancels via the wrapped signal when the timeout elapses', () async {
      final captor = _RequestCaptor();
      final wrapped = timeoutInterceptor(const Duration(milliseconds: 25))(
        captor.next,
      );

      await wrapped(_unaryReq(signal: CancelableSignal()));

      final error = await captor.last!.signal.future;
      expect(error.code, Code.deadlineExceeded);
    });
  });
}

class _RequestCaptor {
  Request<int, int>? last;

  Future<Response<int, int>> next(Request<int, int> req) async {
    last = req;
    return UnaryResponse<int, int>(req.spec, Headers(), 0, Headers());
  }
}

Spec<int, int> _spec() => Spec<int, int>(
  '/example.Service/Method',
  StreamType.unary,
  () => 0,
  () => 0,
  idempotency: Idempotency.idempotent,
);

UnaryRequest<int, int> _unaryReq({required AbortSignal signal}) {
  return UnaryRequest<int, int>(
    _spec(),
    'https://example.invalid/svc/Method',
    Headers(),
    0,
    signal,
  );
}
