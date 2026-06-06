// Copyright 2026 The Pinguteca SDK Authors.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sdk_core_dart_oauth/sdk_core_dart_oauth.dart';
import 'package:test/test.dart';

void main() {
  group('discoverOidc', () {
    test(
      'fetches .well-known/openid-configuration relative to issuer',
      () async {
        Uri? requested;
        final client = MockClient((req) async {
          requested = req.url;
          return _ok({
            'issuer': 'https://idp.example.com',
            'token_endpoint': 'https://idp.example.com/oauth/token',
          });
        });

        final metadata = await discoverOidc(
          OidcDiscoveryConfig(
            issuer: Uri.parse('https://idp.example.com'),
            httpClient: client,
          ),
        );

        expect(
          requested.toString(),
          'https://idp.example.com/.well-known/openid-configuration',
        );
        expect(
          metadata.tokenEndpoint,
          Uri.parse('https://idp.example.com/oauth/token'),
        );
      },
    );

    test('joins .well-known under issuer paths (multi-tenant IdPs)', () async {
      Uri? requested;
      final client = MockClient((req) async {
        requested = req.url;
        return _ok({
          'issuer': 'https://idp.example.com/tenants/acme',
          'token_endpoint': 'https://idp.example.com/tenants/acme/oauth/token',
        });
      });

      await discoverOidc(
        OidcDiscoveryConfig(
          issuer: Uri.parse('https://idp.example.com/tenants/acme/'),
          httpClient: client,
        ),
      );

      expect(
        requested.toString(),
        'https://idp.example.com/tenants/acme/.well-known/openid-configuration',
      );
    });

    test('parses optional fields when present', () async {
      final client = MockClient((req) async {
        return _ok({
          'issuer': 'https://idp.example.com',
          'token_endpoint': 'https://idp.example.com/oauth/token',
          'authorization_endpoint': 'https://idp.example.com/oauth/authorize',
          'jwks_uri': 'https://idp.example.com/.well-known/jwks.json',
          'grant_types_supported': ['client_credentials', 'authorization_code'],
          'token_endpoint_auth_methods_supported': [
            'client_secret_basic',
            'client_secret_post',
          ],
          'scopes_supported': ['openid', 'profile', 'rpc.read'],
        });
      });

      final metadata = await discoverOidc(
        OidcDiscoveryConfig(
          issuer: Uri.parse('https://idp.example.com'),
          httpClient: client,
        ),
      );

      expect(
        metadata.authorizationEndpoint,
        Uri.parse('https://idp.example.com/oauth/authorize'),
      );
      expect(
        metadata.jwksUri,
        Uri.parse('https://idp.example.com/.well-known/jwks.json'),
      );
      expect(
        metadata.grantTypesSupported,
        containsAll(['client_credentials', 'authorization_code']),
      );
      expect(
        metadata.tokenEndpointAuthMethodsSupported,
        contains('client_secret_basic'),
      );
      expect(metadata.scopesSupported, contains('rpc.read'));
    });

    test('rejects an issuer mismatch by default', () async {
      final client = MockClient((req) async {
        return _ok({
          // Mismatched: requested example.com, doc says other.example.
          'issuer': 'https://other.example.com',
          'token_endpoint': 'https://other.example.com/oauth/token',
        });
      });

      await expectLater(
        discoverOidc(
          OidcDiscoveryConfig(
            issuer: Uri.parse('https://idp.example.com'),
            httpClient: client,
          ),
        ),
        throwsA(
          isA<OAuthException>().having(
            (e) => e.message,
            'message',
            contains('issuer mismatch'),
          ),
        ),
      );
    });

    test(
      'tolerates trailing slashes when validating the issuer claim',
      () async {
        final client = MockClient((req) async {
          return _ok({
            'issuer': 'https://idp.example.com/',
            'token_endpoint': 'https://idp.example.com/oauth/token',
          });
        });

        final metadata = await discoverOidc(
          OidcDiscoveryConfig(
            issuer: Uri.parse('https://idp.example.com'),
            httpClient: client,
          ),
        );

        expect(metadata.issuer, Uri.parse('https://idp.example.com/'));
      },
    );

    test('validateIssuer=false lets a mismatch through', () async {
      final client = MockClient((req) async {
        return _ok({
          'issuer': 'https://other.example.com',
          'token_endpoint': 'https://other.example.com/oauth/token',
        });
      });

      final metadata = await discoverOidc(
        OidcDiscoveryConfig(
          issuer: Uri.parse('https://idp.example.com'),
          httpClient: client,
          validateIssuer: false,
        ),
      );

      expect(
        metadata.tokenEndpoint,
        Uri.parse('https://other.example.com/oauth/token'),
      );
    });

    test('throws OAuthException on non-2xx', () async {
      final client = MockClient((req) async {
        return http.Response('upstream down', 503);
      });

      await expectLater(
        discoverOidc(
          OidcDiscoveryConfig(
            issuer: Uri.parse('https://idp.example.com'),
            httpClient: client,
          ),
        ),
        throwsA(
          isA<OAuthException>().having((e) => e.statusCode, 'statusCode', 503),
        ),
      );
    });

    test('throws OAuthException when required fields are missing', () async {
      final client = MockClient((req) async {
        return _ok({'token_endpoint': 'https://idp.example.com/oauth/token'});
      });

      await expectLater(
        discoverOidc(
          OidcDiscoveryConfig(
            issuer: Uri.parse('https://idp.example.com'),
            httpClient: client,
          ),
        ),
        throwsA(
          isA<OAuthException>().having(
            (e) => e.message,
            'message',
            contains('"issuer"'),
          ),
        ),
      );
    });

    test('throws OAuthException on non-JSON bodies', () async {
      final client = MockClient((req) async {
        return http.Response('not json', 200);
      });

      await expectLater(
        discoverOidc(
          OidcDiscoveryConfig(
            issuer: Uri.parse('https://idp.example.com'),
            httpClient: client,
          ),
        ),
        throwsA(
          isA<OAuthException>().having(
            (e) => e.message,
            'message',
            contains('non-JSON'),
          ),
        ),
      );
    });
  });

  group('ClientCredentialsTokenSource.fromIssuer', () {
    test('discovers token endpoint then fetches a token', () async {
      final client = MockClient((req) async {
        final url = req.url.toString();
        if (url.contains('.well-known/openid-configuration')) {
          return _ok({
            'issuer': 'https://idp.example.com',
            'token_endpoint': 'https://idp.example.com/oauth/token',
          });
        }
        if (url == 'https://idp.example.com/oauth/token') {
          return _ok({'access_token': 'discovered-tok', 'expires_in': 3600});
        }
        return http.Response('unexpected $url', 404);
      });

      final source = await ClientCredentialsTokenSource.fromIssuer(
        issuer: Uri.parse('https://idp.example.com'),
        clientId: 'svc-1',
        clientSecret: 'sekret',
        httpClient: client,
      );

      expect(await source.token(), 'discovered-tok');
    });

    test('propagates discovery failures as OAuthException', () async {
      final client = MockClient((req) async {
        return http.Response('nope', 500);
      });

      await expectLater(
        ClientCredentialsTokenSource.fromIssuer(
          issuer: Uri.parse('https://idp.example.com'),
          clientId: 'svc-1',
          clientSecret: 'sekret',
          httpClient: client,
        ),
        throwsA(
          isA<OAuthException>().having((e) => e.statusCode, 'statusCode', 500),
        ),
      );
    });
  });
}

http.Response _ok(Map<String, Object?> body) {
  return http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );
}
