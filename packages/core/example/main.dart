// Pinguteca SDK Core example.
//
// Shows the recommended interceptor stack for a Connect client, outermost
// to innermost, matching RFC 0002 of the cross-SDK contract:
//
//   SdkError -> Timeout -> Idempotency -> Retry -> Auth
//
// The list goes into your Connect client builder verbatim. Generated
// client stubs accept it as an `interceptors` argument.

import 'package:connectrpc/connect.dart';
import 'package:sdk_core_dart/auth.dart';
import 'package:sdk_core_dart/errors.dart';
import 'package:sdk_core_dart/idempotency.dart';
import 'package:sdk_core_dart/retry.dart';
import 'package:sdk_core_dart/timeout.dart';

void main() {
  final tokenSource = FunctionTokenSource(_fetchToken);

  final interceptors = <Interceptor>[
    // Outermost: convert ConnectException into the SDK's stable error type.
    sdkErrorInterceptor(),

    // Per-call deadline. Server-supplied retry hints can still exceed this.
    timeoutInterceptor(const Duration(seconds: 10)),

    // Idempotency key set once, replayed across retry attempts.
    idempotencyKeyInterceptor(),

    // Retry IDEMPOTENT calls on transient codes with exponential
    // backoff + jitter. Defaults are the RFC 0006 values.
    retryInterceptor(),

    // Innermost: refresh credentials on every attempt.
    authInterceptor(AuthConfig(source: tokenSource)),
  ];

  // Pass `interceptors` to your generated Connect client constructor.
  // The list is wired outer-to-inner exactly as printed.
  print('Configured ${interceptors.length} interceptors.');
}

Future<String> _fetchToken() async {
  // In production this calls your IdP. The example returns a static
  // placeholder so the snippet stays self-contained.
  return 'demo-token';
}
