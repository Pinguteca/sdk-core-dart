// Copyright 2026 The Pinguteca SDK Authors.

import 'package:connectrpc/connect.dart';
import 'package:sdk_core_dart/breaker.dart';
import 'package:test/test.dart';

void main() {
  group('circuitBreakerInterceptor', () {
    test('lets calls through while closed', () async {
      final clock = _ManualClock(DateTime.utc(2026, 1, 1));
      final wrapped = circuitBreakerInterceptor(
        CircuitBreakerConfig(now: clock.now),
      )(_okStub(42));

      final response = await wrapped(_unaryReq());

      expect((response as UnaryResponse<int, int>).message, 42);
    });

    test('trips to open after threshold failures inside the window', () async {
      final clock = _ManualClock(DateTime.utc(2026, 1, 1));
      final wrapped = circuitBreakerInterceptor(
        CircuitBreakerConfig(
          failureThreshold: 3,
          window: const Duration(seconds: 10),
          openTimeout: const Duration(seconds: 30),
          now: clock.now,
        ),
      )(_failStub(ConnectException(Code.unavailable, 'flap')));

      // Three failures inside the window trip the breaker.
      for (var i = 0; i < 3; i++) {
        await expectLater(
          wrapped(_unaryReq()),
          throwsA(
            isA<ConnectException>().having((e) => e.message, 'message', 'flap'),
          ),
        );
      }

      // The fourth call short-circuits with a synthetic exception.
      await expectLater(
        wrapped(_unaryReq()),
        throwsA(
          isA<ConnectException>()
              .having((e) => e.code, 'code', Code.unavailable)
              .having(
                (e) => e.message,
                'message',
                contains('circuit breaker open'),
              ),
        ),
      );
    });

    test(
      'failures outside the window do not count toward the threshold',
      () async {
        final clock = _ManualClock(DateTime.utc(2026, 1, 1));
        final wrapped = circuitBreakerInterceptor(
          CircuitBreakerConfig(
            failureThreshold: 3,
            window: const Duration(seconds: 10),
            now: clock.now,
          ),
        )(_failStub(ConnectException(Code.unavailable, 'flap')));

        // Two failures, then advance past the window before the third.
        await expectLater(
          wrapped(_unaryReq()),
          throwsA(isA<ConnectException>()),
        );
        await expectLater(
          wrapped(_unaryReq()),
          throwsA(isA<ConnectException>()),
        );
        clock.advance(const Duration(seconds: 11));
        await expectLater(
          wrapped(_unaryReq()),
          throwsA(isA<ConnectException>()),
        );

        // Breaker still closed because the first two fell out of the window.
        final ok = _captureNextCall();
        final wrapped2 = circuitBreakerInterceptor(
          CircuitBreakerConfig(
            failureThreshold: 3,
            window: const Duration(seconds: 10),
            now: clock.now,
          ),
        )(ok.next);
        await wrapped2(_unaryReq());
        expect(ok.calls, 1);
      },
    );

    test('opens then recovers to half-open after openTimeout', () async {
      final clock = _ManualClock(DateTime.utc(2026, 1, 1));
      var fail = true;
      final wrapped =
          circuitBreakerInterceptor(
            CircuitBreakerConfig(
              failureThreshold: 2,
              openTimeout: const Duration(seconds: 5),
              successThreshold: 1,
              now: clock.now,
            ),
          )(
            _conditionalStub(
              shouldFail: () => fail,
              failure: ConnectException(Code.unavailable, 'flap'),
            ),
          );

      // Trip the breaker.
      await expectLater(wrapped(_unaryReq()), throwsA(isA<ConnectException>()));
      await expectLater(wrapped(_unaryReq()), throwsA(isA<ConnectException>()));

      // Now open: short-circuits.
      await expectLater(
        wrapped(_unaryReq()),
        throwsA(
          isA<ConnectException>().having(
            (e) => e.message,
            'message',
            contains('circuit breaker open'),
          ),
        ),
      );

      // Advance past openTimeout; next call is a half-open trial.
      clock.advance(const Duration(seconds: 6));
      fail = false;
      final response = await wrapped(_unaryReq());
      expect(response, isA<UnaryResponse<int, int>>());

      // Successful trial closed the breaker; subsequent calls pass.
      await wrapped(_unaryReq());
    });

    test('half-open failure re-opens the breaker', () async {
      final clock = _ManualClock(DateTime.utc(2026, 1, 1));
      final wrapped = circuitBreakerInterceptor(
        CircuitBreakerConfig(
          failureThreshold: 1,
          openTimeout: const Duration(seconds: 1),
          now: clock.now,
        ),
      )(_failStub(ConnectException(Code.unavailable, 'flap')));

      // Single failure trips immediately because threshold is 1.
      await expectLater(wrapped(_unaryReq()), throwsA(isA<ConnectException>()));

      // Advance past openTimeout and try again; the half-open trial fails
      // and the breaker re-opens.
      clock.advance(const Duration(seconds: 2));
      await expectLater(
        wrapped(_unaryReq()),
        throwsA(
          isA<ConnectException>().having((e) => e.message, 'message', 'flap'),
        ),
      );

      // Without advancing time again the breaker is still open.
      await expectLater(
        wrapped(_unaryReq()),
        throwsA(
          isA<ConnectException>().having(
            (e) => e.message,
            'message',
            contains('circuit breaker open'),
          ),
        ),
      );
    });

    test('only non-failure codes do not trip the breaker', () async {
      final clock = _ManualClock(DateTime.utc(2026, 1, 1));
      final wrapped = circuitBreakerInterceptor(
        CircuitBreakerConfig(failureThreshold: 2, now: clock.now),
      )(_failStub(ConnectException(Code.invalidArgument, 'bad input')));

      // invalidArgument is not in defaultIsFailure; failures don't accumulate.
      for (var i = 0; i < 5; i++) {
        await expectLater(
          wrapped(_unaryReq()),
          throwsA(
            isA<ConnectException>().having(
              (e) => e.code,
              'code',
              Code.invalidArgument,
            ),
          ),
        );
      }
      // Still no short-circuit:
      await expectLater(
        wrapped(_unaryReq()),
        throwsA(
          isA<ConnectException>().having(
            (e) => e.code,
            'code',
            Code.invalidArgument,
          ),
        ),
      );
    });

    test('keyFn groups state per bucket', () async {
      final clock = _ManualClock(DateTime.utc(2026, 1, 1));
      final wrapped = circuitBreakerInterceptor(
        CircuitBreakerConfig(
          failureThreshold: 2,
          // Group all procedures sharing /example.Service/ into one bucket.
          keyFn: (procedure) => procedure.split('/').take(2).join('/'),
          now: clock.now,
        ),
      )(_failStub(ConnectException(Code.unavailable, 'flap')));

      // Two failures across two different procedures in the same service
      // trip the shared bucket.
      await expectLater(
        wrapped(_unaryReqFor('/example.Service/MethodA')),
        throwsA(isA<ConnectException>()),
      );
      await expectLater(
        wrapped(_unaryReqFor('/example.Service/MethodB')),
        throwsA(isA<ConnectException>()),
      );
      await expectLater(
        wrapped(_unaryReqFor('/example.Service/MethodC')),
        throwsA(
          isA<ConnectException>().having(
            (e) => e.message,
            'message',
            contains('circuit breaker open'),
          ),
        ),
      );
    });

    test(
      'custom isFailure predicate controls what trips the breaker',
      () async {
        final clock = _ManualClock(DateTime.utc(2026, 1, 1));
        final wrapped = circuitBreakerInterceptor(
          CircuitBreakerConfig(
            failureThreshold: 2,
            isFailure: (e) => e.code == Code.permissionDenied,
            now: clock.now,
          ),
        )(_failStub(ConnectException(Code.permissionDenied, 'no')));

        await expectLater(
          wrapped(_unaryReq()),
          throwsA(isA<ConnectException>()),
        );
        await expectLater(
          wrapped(_unaryReq()),
          throwsA(isA<ConnectException>()),
        );
        await expectLater(
          wrapped(_unaryReq()),
          throwsA(
            isA<ConnectException>().having(
              (e) => e.message,
              'message',
              contains('circuit breaker open'),
            ),
          ),
        );
      },
    );
  });

  group('defaultIsFailure', () {
    test('treats transient + server-side codes as failures', () {
      expect(defaultIsFailure(ConnectException(Code.unavailable, '')), isTrue);
      expect(
        defaultIsFailure(ConnectException(Code.resourceExhausted, '')),
        isTrue,
      );
      expect(defaultIsFailure(ConnectException(Code.aborted, '')), isTrue);
      expect(
        defaultIsFailure(ConnectException(Code.deadlineExceeded, '')),
        isTrue,
      );
      expect(defaultIsFailure(ConnectException(Code.internal, '')), isTrue);
      expect(defaultIsFailure(ConnectException(Code.dataLoss, '')), isTrue);
    });

    test('does not flag caller-side codes', () {
      expect(
        defaultIsFailure(ConnectException(Code.invalidArgument, '')),
        isFalse,
      );
      expect(defaultIsFailure(ConnectException(Code.notFound, '')), isFalse);
      expect(
        defaultIsFailure(ConnectException(Code.permissionDenied, '')),
        isFalse,
      );
      expect(
        defaultIsFailure(ConnectException(Code.unauthenticated, '')),
        isFalse,
      );
    });
  });
}

class _ManualClock {
  _ManualClock(this._now);

  DateTime _now;

  DateTime now() => _now;

  void advance(Duration d) {
    _now = _now.add(d);
  }
}

class _Captor {
  int calls = 0;
  Future<Response<int, int>> next(Request<int, int> req) async {
    calls++;
    return UnaryResponse<int, int>(req.spec, Headers(), 0, Headers());
  }
}

_Captor _captureNextCall() => _Captor();

AnyFn<int, int> _okStub(int message) {
  return (Request<int, int> req) async {
    return UnaryResponse<int, int>(req.spec, Headers(), message, Headers());
  };
}

AnyFn<int, int> _failStub(ConnectException error) {
  return (Request<int, int> req) async {
    throw error;
  };
}

AnyFn<int, int> _conditionalStub({
  required bool Function() shouldFail,
  required ConnectException failure,
}) {
  return (Request<int, int> req) async {
    if (shouldFail()) {
      throw failure;
    }
    return UnaryResponse<int, int>(req.spec, Headers(), 0, Headers());
  };
}

UnaryRequest<int, int> _unaryReq() => _unaryReqFor('/example.Service/Method');

UnaryRequest<int, int> _unaryReqFor(String procedure) {
  return UnaryRequest<int, int>(
    Spec<int, int>(procedure, StreamType.unary, () => 0, () => 0),
    'https://example.invalid$procedure',
    Headers(),
    0,
    CancelableSignal(),
  );
}
