// Copyright 2026 The Pinguteca SDK Authors.

import 'dart:typed_data';

import 'package:connectrpc/connect.dart';
import 'package:sdk_core_dart/retry.dart';
import 'package:test/test.dart';

void main() {
  group('retryInterceptor', () {
    test('returns the response without retry on success', () async {
      final spy = _SleepSpy();
      final wrapped = retryInterceptor(_fastConfig(sleep: spy.sleep))(
        _stub([_ok(42)]),
      );

      final response = await wrapped(_unaryReq(spec: _idempotentSpec()));

      expect((response as UnaryResponse<int, int>).message, 42);
      expect(spy.calls, isEmpty);
    });

    test('retries on a retryable code until success', () async {
      final spy = _SleepSpy();
      final wrapped = retryInterceptor(_fastConfig(sleep: spy.sleep))(
        _stub([_err(Code.unavailable), _err(Code.unavailable), _ok(7)]),
      );

      final response = await wrapped(_unaryReq(spec: _idempotentSpec()));

      expect((response as UnaryResponse<int, int>).message, 7);
      expect(spy.calls, hasLength(2));
    });

    test('stops at maxAttempts and rethrows the last error', () async {
      final spy = _SleepSpy();
      final wrapped =
          retryInterceptor(_fastConfig(sleep: spy.sleep, maxAttempts: 3))(
            _stub([
              _err(Code.unavailable),
              _err(Code.unavailable),
              _err(Code.unavailable),
              _ok(99),
            ]),
          );

      await expectLater(
        wrapped(_unaryReq(spec: _idempotentSpec())),
        throwsA(
          isA<ConnectException>().having(
            (e) => e.code,
            'code',
            Code.unavailable,
          ),
        ),
      );
      expect(spy.calls, hasLength(2));
    });

    test('does not retry codes outside the retryable set', () async {
      final spy = _SleepSpy();
      final wrapped = retryInterceptor(_fastConfig(sleep: spy.sleep))(
        _stub([_err(Code.invalidArgument), _ok(1)]),
      );

      await expectLater(
        wrapped(_unaryReq(spec: _idempotentSpec())),
        throwsA(isA<ConnectException>()),
      );
      expect(spy.calls, isEmpty);
    });

    test(
      'skips retry when the schema does not declare the method idempotent',
      () async {
        final spy = _SleepSpy();
        final wrapped = retryInterceptor(_fastConfig(sleep: spy.sleep))(
          _stub([_err(Code.unavailable), _ok(0)]),
        );

        await expectLater(
          wrapped(_unaryReq(spec: _unknownIdempotencySpec())),
          throwsA(isA<ConnectException>()),
        );
        expect(spy.calls, isEmpty);
      },
    );

    test('allowNonIdempotent bypasses the gate', () async {
      final spy = _SleepSpy();
      final wrapped = retryInterceptor(
        _fastConfig(sleep: spy.sleep, allowNonIdempotent: true),
      )(_stub([_err(Code.unavailable), _ok(5)]));

      final response = await wrapped(
        _unaryReq(spec: _unknownIdempotencySpec()),
      );

      expect((response as UnaryResponse<int, int>).message, 5);
      expect(spy.calls, hasLength(1));
    });

    test('streaming requests pass through untouched', () async {
      final spy = _SleepSpy();
      final wrapped = retryInterceptor(_fastConfig(sleep: spy.sleep))(
        _stub([_err(Code.unavailable), _ok(0)]),
      );

      await expectLater(
        wrapped(_unaryReq(spec: _streamingSpec())),
        throwsA(isA<ConnectException>()),
      );
      expect(spy.calls, isEmpty);
    });

    test('honors retry-after header when honorRetryAfter is true', () async {
      final spy = _SleepSpy();
      final wrapped = retryInterceptor(_fastConfig(sleep: spy.sleep))(
        _stub([_err(Code.unavailable, retryAfterSeconds: 2), _ok(0)]),
      );

      await wrapped(_unaryReq(spec: _idempotentSpec()));

      expect(spy.calls.single, const Duration(seconds: 2));
    });

    test('ignores retry-after when honorRetryAfter is false', () async {
      final spy = _SleepSpy();
      final wrapped = retryInterceptor(
        _fastConfig(
          sleep: spy.sleep,
          honorRetryAfter: false,
          jitterSource: () => 0.0,
        ),
      )(_stub([_err(Code.unavailable, retryAfterSeconds: 60), _ok(0)]));

      await wrapped(_unaryReq(spec: _idempotentSpec()));

      expect(spy.calls.single, lessThan(const Duration(seconds: 1)));
    });

    test('RetryInfo detail wins over retry-after header', () async {
      final spy = _SleepSpy();
      final wrapped = retryInterceptor(_fastConfig(sleep: spy.sleep))(
        _stub([
          _err(Code.unavailable, retryAfterSeconds: 60, retryInfoSeconds: 4),
          _ok(0),
        ]),
      );

      await wrapped(_unaryReq(spec: _idempotentSpec()));

      expect(spy.calls.single, const Duration(seconds: 4));
    });

    test('custom isRetryable predicate overrides the code set', () async {
      final spy = _SleepSpy();
      final wrapped = retryInterceptor(
        _fastConfig(
          sleep: spy.sleep,
          isRetryable: (error) => error.code == Code.invalidArgument,
        ),
      )(_stub([_err(Code.invalidArgument), _ok(11)]));

      final response = await wrapped(_unaryReq(spec: _idempotentSpec()));

      expect((response as UnaryResponse<int, int>).message, 11);
    });

    test('jitter draws stay within the per-attempt ceiling', () async {
      final spy = _SleepSpy();
      final wrapped =
          retryInterceptor(
            _fastConfig(
              sleep: spy.sleep,
              initial: const Duration(milliseconds: 100),
              max: const Duration(seconds: 1),
              multiplier: 2.0,
              jitterSource: () => 0.999999,
            ),
          )(
            _stub([
              _err(Code.unavailable),
              _err(Code.unavailable),
              _err(Code.unavailable),
              _ok(0),
            ]),
          );

      await wrapped(_unaryReq(spec: _idempotentSpec()));

      // Attempts 1, 2, 3 use ceilings: initial (100ms), initial*2 (200ms), initial*4 (400ms).
      // With jitter near 1.0 the draws hug the ceiling but never exceed it.
      expect(
        spy.calls[0],
        lessThanOrEqualTo(const Duration(milliseconds: 100)),
      );
      expect(
        spy.calls[1],
        lessThanOrEqualTo(const Duration(milliseconds: 200)),
      );
      expect(
        spy.calls[2],
        lessThanOrEqualTo(const Duration(milliseconds: 400)),
      );
    });

    test(
      'decorrelated strategy uses previous delay as the upper basis',
      () async {
        final spy = _SleepSpy();
        final wrapped = retryInterceptor(
          _fastConfig(
            sleep: spy.sleep,
            strategy: RetryStrategy.decorrelated,
            initial: const Duration(milliseconds: 50),
            max: const Duration(seconds: 5),
            decorrelationFactor: 3.0,
            jitterSource: () => 0.999999,
          ),
        )(_stub([_err(Code.unavailable), _err(Code.unavailable), _ok(0)]));

        await wrapped(_unaryReq(spec: _idempotentSpec()));

        // First decorrelated draw: upper = min(max, initial * 3) = 150ms.
        expect(
          spy.calls[0],
          lessThanOrEqualTo(const Duration(milliseconds: 150)),
        );
        expect(
          spy.calls[0],
          greaterThanOrEqualTo(const Duration(milliseconds: 50)),
        );
        // Second draw: upper = min(max, prev * 3). prev was <= 150ms so upper <= 450ms.
        expect(
          spy.calls[1],
          lessThanOrEqualTo(const Duration(milliseconds: 450)),
        );
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

RetryConfig _fastConfig({
  required Future<void> Function(Duration) sleep,
  int maxAttempts = 4,
  bool honorRetryAfter = true,
  bool allowNonIdempotent = false,
  RetryStrategy strategy = RetryStrategy.full,
  Duration initial = const Duration(milliseconds: 1),
  Duration max = const Duration(milliseconds: 10),
  double multiplier = 2.0,
  double decorrelationFactor = 3.0,
  bool Function(ConnectException)? isRetryable,
  double Function()? jitterSource,
}) {
  return RetryConfig(
    maxAttempts: maxAttempts,
    initial: initial,
    max: max,
    multiplier: multiplier,
    decorrelationFactor: decorrelationFactor,
    strategy: strategy,
    honorRetryAfter: honorRetryAfter,
    allowNonIdempotent: allowNonIdempotent,
    isRetryable: isRetryable,
    jitterSource: jitterSource ?? () => 0.0,
    sleep: sleep,
  );
}

class _SleepSpy {
  final calls = <Duration>[];
  Future<void> sleep(Duration d) {
    calls.add(d);
    return Future.value();
  }
}

/// Either a UnaryResponse to return or a ConnectException to throw.
sealed class _Outcome {}

class _OkOutcome implements _Outcome {
  _OkOutcome(this.message);
  final int message;
}

class _ErrOutcome implements _Outcome {
  _ErrOutcome(this.error);
  final ConnectException error;
}

_OkOutcome _ok(int v) => _OkOutcome(v);

_ErrOutcome _err(Code code, {int? retryAfterSeconds, int? retryInfoSeconds}) {
  final metadata = Headers();
  if (retryAfterSeconds != null) {
    metadata['retry-after'] = retryAfterSeconds.toString();
  }
  final details = <ErrorDetail>[];
  if (retryInfoSeconds != null) {
    details.add(
      ErrorDetail('google.rpc.RetryInfo', _encodeRetryInfo(retryInfoSeconds)),
    );
  }
  return _ErrOutcome(
    ConnectException(code, 'test', metadata: metadata, details: details),
  );
}

/// Returns an AnyFn that walks through the supplied outcomes in order.
AnyFn<int, int> _stub(List<_Outcome> outcomes) {
  var i = 0;
  return (Request<int, int> req) async {
    if (i >= outcomes.length) {
      throw StateError('next called more times than the stub allows');
    }
    final outcome = outcomes[i++];
    switch (outcome) {
      case _OkOutcome(message: final m):
        return UnaryResponse<int, int>(req.spec, Headers(), m, Headers());
      case _ErrOutcome(error: final e):
        throw e;
    }
  };
}

UnaryRequest<int, int> _unaryReq({required Spec<int, int> spec}) {
  return UnaryRequest<int, int>(
    spec,
    'https://example.invalid/retry',
    Headers(),
    0,
    CancelableSignal(),
  );
}

Spec<int, int> _idempotentSpec() => Spec<int, int>(
  '/example.Service/Method',
  StreamType.unary,
  () => 0,
  () => 0,
  idempotency: Idempotency.idempotent,
);

Spec<int, int> _unknownIdempotencySpec() => Spec<int, int>(
  '/example.Service/Method',
  StreamType.unary,
  () => 0,
  () => 0,
);

Spec<int, int> _streamingSpec() => Spec<int, int>(
  '/example.Service/StreamMethod',
  StreamType.server,
  () => 0,
  () => 0,
  idempotency: Idempotency.idempotent,
);

/// Encodes a RetryInfo with `retry_delay = seconds`, no nanos. Bytes match
/// the canonical wire format the production decoder consumes.
Uint8List _encodeRetryInfo(int seconds) {
  final duration = <int>[
    0x08, // field 1 (seconds), varint
    ..._varint(seconds),
  ];
  return Uint8List.fromList(<int>[
    0x0A, // field 1 (retry_delay), length-delimited
    duration.length,
    ...duration,
  ]);
}

List<int> _varint(int value) {
  final bytes = <int>[];
  var v = value;
  while ((v & ~0x7F) != 0) {
    bytes.add((v & 0x7F) | 0x80);
    v >>= 7;
  }
  bytes.add(v & 0x7F);
  return bytes;
}
