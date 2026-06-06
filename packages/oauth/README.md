# sdk_core_dart_oauth

> [!WARNING]
> **Work in progress, not production-ready.** APIs are unstable and may
> change without notice before the first stable release.

OAuth 2.0 lifecycle helpers for the Pinguteca Dart SDK. Layer 3 companion to
[`sdk_core_dart`](https://pub.dev/packages/sdk_core_dart): pulls in
[`package:http`](https://pub.dev/packages/http) and implements
[RFC 6749](https://datatracker.ietf.org/doc/html/rfc6749) grant flows so
consumers do not have to.

## What ships

- `ClientCredentialsTokenSource`: server-to-server `client_credentials`
  grant flow with token cache, expiry-aware refresh, and single-flight
  deduplication of concurrent refreshes.
- `OAuthException`: typed error surface for token-endpoint failures.

Plugs directly into the L2 auth interceptor via the `TokenSource`
contract from `package:sdk_core_dart/auth.dart`:

```dart
import 'package:sdk_core_dart/auth.dart';
import 'package:sdk_core_dart_oauth/sdk_core_dart_oauth.dart';

final tokenSource = ClientCredentialsTokenSource(
  ClientCredentialsConfig(
    tokenEndpoint: Uri.parse('https://idp.example.com/oauth/token'),
    clientId: 'svc-1',
    clientSecret: 'secret',
    scopes: const ['rpc.read', 'rpc.write'],
  ),
);

final interceptor = authInterceptor(AuthConfig(source: tokenSource));
```

## Roadmap

- `authorization_code` with PKCE for desktop and mobile clients.
- OIDC discovery so callers configure only the issuer URL.
- mTLS client-cert authentication for the token endpoint.

## License

Apache-2.0. See `LICENSE`.
