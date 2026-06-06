// Copyright 2026 The Pinguteca SDK Authors.
//
// mTLS auth-mode tests. Verify the grant flows omit Basic auth and
// client_secret when ClientAuthMode.mtls is selected. The actual TLS
// handshake is exercised in integration tests against a real IdP; here
// we only check the on-wire shape.

@TestOn('vm')
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sdk_core_dart_oauth/sdk_core_dart_oauth.dart';
import 'package:test/test.dart';

void main() {
  group('ClientAuthMode.mtls on client_credentials', () {
    test('omits Basic auth and client_secret; sends client_id only', () async {
      http.Request? captured;
      final source = ClientCredentialsTokenSource(
        ClientCredentialsConfig(
          tokenEndpoint: Uri.parse('https://idp.example.com/oauth/token'),
          clientId: 'mtls-client',
          // Empty secret is fine for mtls: the field is ignored.
          clientSecret: '',
          authMode: ClientAuthMode.mtls,
          httpClient: MockClient((req) async {
            captured = req;
            return http.Response(
              jsonEncode({'access_token': 'tok', 'expires_in': 3600}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );

      await source.token();

      expect(captured!.headers['authorization'], isNull);
      expect(captured!.body, contains('client_id=mtls-client'));
      expect(captured!.body, isNot(contains('client_secret=')));
    });
  });

  group('ClientAuthMode.mtls on authorization_code', () {
    test('exchange omits Basic auth and client_secret', () async {
      http.Request? captured;
      final flow = AuthorizationCodeFlow(
        AuthorizationCodeConfig(
          authorizationEndpoint: Uri.parse(
            'https://idp.example.com/oauth/authorize',
          ),
          tokenEndpoint: Uri.parse('https://idp.example.com/oauth/token'),
          clientId: 'mtls-client',
          redirectUri: Uri.parse('https://app.example.com/callback'),
          clientAuthMode: ClientAuthMode.mtls,
          httpClient: MockClient((req) async {
            captured = req;
            return http.Response(
              jsonEncode({'access_token': 'tok', 'expires_in': 3600}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );

      await flow.exchange(code: 'auth-code', codeVerifier: 'a' * 43);

      expect(captured!.headers['authorization'], isNull);
      expect(captured!.body, contains('client_id=mtls-client'));
      expect(captured!.body, isNot(contains('client_secret=')));
    });

    test('refresh omits Basic auth and client_secret', () async {
      http.Request? captured;
      final flow = AuthorizationCodeFlow(
        AuthorizationCodeConfig(
          authorizationEndpoint: Uri.parse(
            'https://idp.example.com/oauth/authorize',
          ),
          tokenEndpoint: Uri.parse('https://idp.example.com/oauth/token'),
          clientId: 'mtls-client',
          redirectUri: Uri.parse('https://app.example.com/callback'),
          clientAuthMode: ClientAuthMode.mtls,
          httpClient: MockClient((req) async {
            captured = req;
            return http.Response(
              jsonEncode({'access_token': 'tok-2', 'expires_in': 3600}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );

      await flow.refresh(refreshToken: 'r-1');

      expect(captured!.headers['authorization'], isNull);
      expect(captured!.body, contains('grant_type=refresh_token'));
      expect(captured!.body, contains('client_id=mtls-client'));
    });
  });

  group('MtlsConfig', () {
    test('captures every PEM path and the optional password', () {
      const config = MtlsConfig(
        certificateChainPath: '/etc/ssl/client.crt.pem',
        privateKeyPath: '/etc/ssl/client.key.pem',
        privateKeyPassword: 'secret',
        trustedCertificatesPath: '/etc/ssl/private-ca.pem',
      );
      expect(config.certificateChainPath, '/etc/ssl/client.crt.pem');
      expect(config.privateKeyPath, '/etc/ssl/client.key.pem');
      expect(config.privateKeyPassword, 'secret');
      expect(config.trustedCertificatesPath, '/etc/ssl/private-ca.pem');
    });
  });
}
