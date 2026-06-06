# sdk_core_dart

> [!WARNING]
> **Work in progress, not production-ready.** APIs are unstable and may
> change without notice before the first stable release.

Layer 2 interceptors and primitives for Pinguteca SDKs in Dart, built on
[`package:connectrpc`](https://pub.dev/packages/connectrpc).

## What ships

| Import | Provides |
|--------|----------|
| `package:sdk_core_dart/retry.dart` | Exponential backoff + jitter, idempotency safety gate, server retry-hint support (RFC 0006) |
| `package:sdk_core_dart/timeout.dart` | Per-call deadlines via `TimeoutSignal`; transports auto-derive timeout headers |
| `package:sdk_core_dart/idempotency.dart` | Auto-generated `idempotency-key` header, 128-bit hex from `Random.secure` |
| `package:sdk_core_dart/auth.dart` | Bearer / API-key injection via a `TokenSource` abstraction |
| `package:sdk_core_dart/errors.dart` | `SdkError` typed boundary; consumers do not need to import `connectrpc` |

## Install

```yaml
dependencies:
  sdk_core_dart: ^0.0.1
```

## Composition

Recommended interceptor order, outermost to innermost:

```
SdkError -> OTel -> Breaker -> Idempotency -> Retry -> Auth
```

The `SdkError` interceptor wraps every `ConnectException` so callers catch
one stable type; retry runs inside the breaker so short-circuited calls
do not consume retry budget; auth runs innermost so a refreshed token
is fetched on every retry attempt.

## Repository

Source, ADRs, and tracking issues at
[github.com/Pinguteca/sdk-core-dart](https://github.com/Pinguteca/sdk-core-dart).

## License

Apache-2.0. See `LICENSE`.
