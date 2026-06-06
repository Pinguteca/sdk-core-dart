// Copyright 2026 The Pinguteca SDK Authors.

import 'dart:async';

import 'package:connectrpc/connect.dart';
import 'package:sdk_core_dart/hedge.dart';
import 'package:test/test.dart';

void main() {
  group('hedgeInterceptor', () {
    test('rejects non-positive hedgeCount or hedgeDelay', () {
      expect(
        () => hedgeInterceptor(const HedgeConfig(hedgeCount: 0)),
        throwsArgumentError,
      );
      expect(
        () => hedgeInterceptor(const HedgeConfig(hedgeDelay: Duration.zero)),
        throwsArgumentError,
      );
    });

    test(
      'passes ineligible (IDEMPOTENT) calls through with no hedge',
      () async {
        var calls = 0;
        final wrapped =
            hedgeInterceptor(
              const HedgeConfig(
                hedgeCount: 2,
                hedgeDelay: Duration(milliseconds: 5),
              ),
            )(
              _stub((req) async {
                calls++;
                return UnaryResponse<int, int>(
                  req.spec,
                  Headers(),
                  1,
                  Headers(),
                );
              }),
            );

        await wrapped(_unaryReq(idempotency: Idempotency.idempotent));

        expect(calls, 1);
      },
    );

    test(
      'hedges NO_SIDE_EFFECTS calls and returns the first success',
      () async {
        var calls = 0;
        final wrapped =
            hedgeInterceptor(
              const HedgeConfig(
                hedgeCount: 2,
                hedgeDelay: Duration(milliseconds: 5),
              ),
            )(
              _stub((req) async {
                final attempt = ++calls;
                // First attempt is slow; later attempts win.
                if (attempt == 1) {
                  await Future<void>.delayed(const Duration(milliseconds: 200));
                }
                return UnaryResponse<int, int>(
                  req.spec,
                  Headers(),
                  attempt,
                  Headers(),
                );
              }),
            );

        final response = await wrapped(
          _unaryReq(idempotency: Idempotency.noSideEffects),
        );

        final message = (response as UnaryResponse<int, int>).message;
        expect(message, isNot(equals(1)));
        expect(calls, greaterThan(1));
      },
    );

    test(
      'returns the primary response when it beats the first hedge',
      () async {
        var calls = 0;
        final wrapped =
            hedgeInterceptor(
              const HedgeConfig(
                hedgeCount: 1,
                hedgeDelay: Duration(milliseconds: 50),
              ),
            )(
              _stub((req) async {
                calls++;
                return UnaryResponse<int, int>(
                  req.spec,
                  Headers(),
                  7,
                  Headers(),
                );
              }),
            );

        final response = await wrapped(
          _unaryReq(idempotency: Idempotency.noSideEffects),
        );

        expect((response as UnaryResponse<int, int>).message, 7);
        // Primary completes immediately; the hedge timer never fires.
        expect(calls, 1);
      },
    );

    test('completes with the last error when every attempt fails', () async {
      final errors = <ConnectException>[
        ConnectException(Code.unavailable, 'first'),
        ConnectException(Code.unavailable, 'second'),
      ];
      var i = 0;
      final wrapped =
          hedgeInterceptor(
            const HedgeConfig(
              hedgeCount: 1,
              hedgeDelay: Duration(milliseconds: 5),
            ),
          )(
            _stub((req) async {
              throw errors[i++];
            }),
          );

      await expectLater(
        wrapped(_unaryReq(idempotency: Idempotency.noSideEffects)),
        throwsA(isA<ConnectException>()),
      );
    });

    test('cancels losers when a hedge wins', () async {
      final cancelled = <int>[];
      var calls = 0;
      final wrapped =
          hedgeInterceptor(
            const HedgeConfig(
              hedgeCount: 1,
              hedgeDelay: Duration(milliseconds: 5),
            ),
          )(
            _stub((req) async {
              final id = ++calls;
              // First attempt blocks until its signal aborts; second wins.
              if (id == 1) {
                try {
                  await req.signal.future;
                  cancelled.add(id);
                } catch (_) {
                  cancelled.add(id);
                }
                throw ConnectException(Code.canceled, 'aborted');
              }
              return UnaryResponse<int, int>(
                req.spec,
                Headers(),
                id,
                Headers(),
              );
            }),
          );

      final response = await wrapped(
        _unaryReq(idempotency: Idempotency.noSideEffects),
      );

      expect((response as UnaryResponse<int, int>).message, 2);
      // Let the abort signal propagate.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(cancelled, contains(1));
    });

    test('custom isEligible predicate controls hedging', () async {
      var calls = 0;
      final wrapped =
          hedgeInterceptor(
            HedgeConfig(
              hedgeCount: 1,
              hedgeDelay: const Duration(milliseconds: 5),
              // Hedge IDEMPOTENT methods too.
              isEligible: <I extends Object, O extends Object>(req) =>
                  req.spec.idempotency != null,
            ),
          )(
            _stub((req) async {
              final id = ++calls;
              if (id == 1) {
                await Future<void>.delayed(const Duration(milliseconds: 200));
              }
              return UnaryResponse<int, int>(
                req.spec,
                Headers(),
                id,
                Headers(),
              );
            }),
          );

      await wrapped(_unaryReq(idempotency: Idempotency.idempotent));

      expect(calls, greaterThan(1));
    });

    test('streaming requests pass through unchanged', () async {
      var calls = 0;
      final wrapped =
          hedgeInterceptor(
            const HedgeConfig(
              hedgeCount: 2,
              hedgeDelay: Duration(milliseconds: 5),
            ),
          )(
            _stub((req) async {
              calls++;
              return UnaryResponse<int, int>(req.spec, Headers(), 0, Headers());
            }),
          );
      final req = StreamRequest<int, int>(
        Spec<int, int>(
          '/example.Service/Stream',
          StreamType.bidi,
          () => 0,
          () => 0,
          idempotency: Idempotency.noSideEffects,
        ),
        'https://example.invalid/svc/Stream',
        Headers(),
        const Stream<int>.empty(),
        CancelableSignal(),
      );

      await wrapped(req);

      expect(calls, 1);
    });
  });
}

AnyFn<int, int> _stub(
  Future<Response<int, int>> Function(Request<int, int>) handler,
) {
  return handler;
}

UnaryRequest<int, int> _unaryReq({required Idempotency? idempotency}) {
  return UnaryRequest<int, int>(
    Spec<int, int>(
      '/example.Service/Method',
      StreamType.unary,
      () => 0,
      () => 0,
      idempotency: idempotency,
    ),
    'https://example.invalid/svc/Method',
    Headers(),
    0,
    CancelableSignal(),
  );
}
