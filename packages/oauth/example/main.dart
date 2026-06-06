// sdk_core_dart_oauth example.
//
// Wires a client_credentials token source into the L2 auth interceptor.

import 'package:sdk_core_dart/auth.dart';
import 'package:sdk_core_dart_oauth/sdk_core_dart_oauth.dart';

void main() {
  final tokenSource = ClientCredentialsTokenSource(
    ClientCredentialsConfig(
      tokenEndpoint: Uri.parse('https://idp.example.com/oauth/token'),
      clientId: 'svc-rpc-1',
      clientSecret: const String.fromEnvironment('OAUTH_CLIENT_SECRET'),
      scopes: const ['rpc.read', 'rpc.write'],
    ),
  );

  final interceptor = authInterceptor(AuthConfig(source: tokenSource));

  // Pass `interceptor` (alongside any L2 interceptors) to your generated
  // Connect client constructor. The first RPC fetches a token; subsequent
  // RPCs reuse the cache until the expires_in window closes.
  print('Configured client_credentials token source for $interceptor.');
}
