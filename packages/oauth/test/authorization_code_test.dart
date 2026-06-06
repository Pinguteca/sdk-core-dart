// Copyright 2026 The Pinguteca SDK Authors.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sdk_core_dart_oauth/sdk_core_dart_oauth.dart';
import 'package:test/test.dart';

void main() {
  group('AuthorizationCodeFlow.buildAuthorizationUrl', () {
    test('puts every required parameter in the query string', () {
      final flow = AuthorizationCodeFlow(_publicConfig());
      final pkce = PkcePair.fromVerifier('a' * 43);

      final url = flow.buildAuthorizationUrl(state: 'st-1', pkce: pkce);

      expect(url.queryParameters['response_type'], 'code');
      expect(url.queryParameters['client_id'], 'svc-1');
      expect(
        url.queryParameters['redirect_uri'],
        'https://app.example.com/callback',
      );
      expect(url.queryParameters['state'], 'st-1');
      expect(url.queryParameters['code_challenge'], pkce.codeChallenge);
      expect(url.queryParameters['code_challenge_method'], 'S256');
      expect(url.queryParameters['scope'], 'openid offline_access');
    });

    test('passes optional nonce and extras through', () {
      final flow = AuthorizationCodeFlow(_publicConfig());
      final pkce = PkcePair.fromVerifier('a' * 43);

      final url = flow.buildAuthorizationUrl(
        state: 'st-1',
        pkce: pkce,
        nonce: 'n-1',
        extraParams: {'prompt': 'consent', 'audience': 'api.example.com'},
      );

      expect(url.queryParameters['nonce'], 'n-1');
      expect(url.queryParameters['prompt'], 'consent');
      expect(url.queryParameters['audience'], 'api.example.com');
    });

    test('preserves query parameters already on the endpoint', () {
      final flow = AuthorizationCodeFlow(
        _publicConfig(
          authorizationEndpoint: Uri.parse(
            'https://idp.example.com/oauth/authorize?tenant=acme',
          ),
        ),
      );
      final pkce = PkcePair.fromVerifier('a' * 43);

      final url = flow.buildAuthorizationUrl(state: 'st-1', pkce: pkce);

      expect(url.queryParameters['tenant'], 'acme');
      expect(url.queryParameters['state'], 'st-1');
    });
  });

  group('AuthorizationCodeFlow.exchange', () {
    test(
      'posts code + verifier with public-client credentials inline',
      () async {
        http.Request? captured;
        final flow = AuthorizationCodeFlow(
          _publicConfig(
            httpClient: MockClient((req) async {
              captured = req;
              return _ok({
                'access_token': 'access-1',
                'refresh_token': 'refresh-1',
                'expires_in': 3600,
                'scope': 'openid offline_access',
              });
            }),
          ),
        );

        final tokens = await flow.exchange(
          code: 'auth-code-1',
          codeVerifier: 'a' * 43,
        );

        expect(captured!.url.toString(), 'https://idp.example.com/oauth/token');
        expect(captured!.body, contains('grant_type=authorization_code'));
        expect(captured!.body, contains('code=auth-code-1'));
        expect(captured!.body, contains('code_verifier=${'a' * 43}'));
        expect(captured!.body, contains('client_id=svc-1'));
        expect(captured!.body, isNot(contains('client_secret=')));
        expect(captured!.headers['authorization'], isNull);

        expect(tokens.accessToken, 'access-1');
        expect(tokens.refreshToken, 'refresh-1');
        expect(tokens.scopes, ['openid', 'offline_access']);
        expect(tokens.expiresIn, const Duration(seconds: 3600));
      },
    );

    test('uses Basic auth when a confidential clientSecret is set', () async {
      http.Request? captured;
      final flow = AuthorizationCodeFlow(
        _confidentialConfig(
          httpClient: MockClient((req) async {
            captured = req;
            return _ok({'access_token': 'access-1', 'expires_in': 3600});
          }),
        ),
      );

      await flow.exchange(code: 'c', codeVerifier: 'a' * 43);

      expect(
        captured!.headers['authorization'],
        'Basic ${base64Encode(utf8.encode('svc-1:sekret'))}',
      );
      expect(captured!.body, isNot(contains('client_secret=')));
    });

    test('throws OAuthException on non-2xx from the token endpoint', () async {
      final flow = AuthorizationCodeFlow(
        _publicConfig(
          httpClient: MockClient((req) async {
            return http.Response('{"error":"invalid_grant"}', 400);
          }),
        ),
      );

      await expectLater(
        flow.exchange(code: 'c', codeVerifier: 'a' * 43),
        throwsA(
          isA<OAuthException>().having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
    });
  });

  group('AuthorizationCodeFlow.refresh', () {
    test('posts grant_type=refresh_token with the supplied token', () async {
      http.Request? captured;
      final flow = AuthorizationCodeFlow(
        _publicConfig(
          httpClient: MockClient((req) async {
            captured = req;
            return _ok({
              'access_token': 'access-2',
              'refresh_token': 'refresh-2',
              'expires_in': 3600,
            });
          }),
        ),
      );

      final tokens = await flow.refresh(refreshToken: 'refresh-1');

      expect(captured!.body, contains('grant_type=refresh_token'));
      expect(captured!.body, contains('refresh_token=refresh-1'));
      expect(tokens.refreshToken, 'refresh-2');
    });
  });

  group('AuthorizationCodeTokenSource', () {
    test('rejects an initial response without a refresh token', () {
      final flow = AuthorizationCodeFlow(_publicConfig());
      const initial = TokenResponse(
        accessToken: 'access-1',
        expiresIn: Duration(seconds: 3600),
        raw: {},
      );

      expect(
        () => AuthorizationCodeTokenSource.fromInitial(
          flow: flow,
          initial: initial,
        ),
        throwsArgumentError,
      );
    });

    test(
      'returns the cached access token until early refresh window',
      () async {
        var now = DateTime.utc(2026, 1, 1);
        var hits = 0;
        final flow = AuthorizationCodeFlow(
          _publicConfig(
            now: () => now,
            httpClient: MockClient((req) async {
              hits++;
              return _ok({
                'access_token': 'access-$hits',
                'refresh_token': 'refresh-$hits',
                'expires_in': 120,
              });
            }),
          ),
        );
        final source = AuthorizationCodeTokenSource.fromInitial(
          flow: flow,
          initial: const TokenResponse(
            accessToken: 'access-initial',
            refreshToken: 'refresh-0',
            expiresIn: Duration(seconds: 120),
            raw: {},
          ),
        );

        expect(await source.token(), 'access-initial');
        now = now.add(const Duration(seconds: 30));
        expect(await source.token(), 'access-initial');
        expect(hits, 0);
      },
    );

    test('refreshes via refresh_token and rotates the stored token', () async {
      var now = DateTime.utc(2026, 1, 1);
      var hits = 0;
      String? lastRefreshSent;
      final flow = AuthorizationCodeFlow(
        _publicConfig(
          now: () => now,
          httpClient: MockClient((req) async {
            hits++;
            final body = req.bodyFields;
            lastRefreshSent = body['refresh_token'];
            return _ok({
              'access_token': 'access-$hits',
              'refresh_token': 'refresh-$hits',
              'expires_in': 3600,
            });
          }),
        ),
      );
      final source = AuthorizationCodeTokenSource.fromInitial(
        flow: flow,
        initial: const TokenResponse(
          accessToken: 'access-0',
          refreshToken: 'refresh-0',
          expiresIn: Duration(seconds: 120),
          raw: {},
        ),
      );

      // Advance past earlyRefresh.
      now = now.add(const Duration(seconds: 90));
      expect(await source.token(), 'access-1');
      expect(lastRefreshSent, 'refresh-0');
      expect(source.refreshToken, 'refresh-1');

      // Advance again; uses the rotated token.
      now = now.add(const Duration(hours: 1));
      expect(await source.token(), 'access-2');
      expect(lastRefreshSent, 'refresh-1');
    });
  });
}

AuthorizationCodeConfig _publicConfig({
  Uri? authorizationEndpoint,
  http.Client? httpClient,
  DateTime Function()? now,
}) {
  return AuthorizationCodeConfig(
    authorizationEndpoint:
        authorizationEndpoint ??
        Uri.parse('https://idp.example.com/oauth/authorize'),
    tokenEndpoint: Uri.parse('https://idp.example.com/oauth/token'),
    clientId: 'svc-1',
    redirectUri: Uri.parse('https://app.example.com/callback'),
    scopes: const ['openid', 'offline_access'],
    httpClient: httpClient,
    now: now,
  );
}

AuthorizationCodeConfig _confidentialConfig({http.Client? httpClient}) {
  return AuthorizationCodeConfig(
    authorizationEndpoint: Uri.parse('https://idp.example.com/oauth/authorize'),
    tokenEndpoint: Uri.parse('https://idp.example.com/oauth/token'),
    clientId: 'svc-1',
    clientSecret: 'sekret',
    redirectUri: Uri.parse('https://app.example.com/callback'),
    scopes: const ['openid'],
    httpClient: httpClient,
  );
}

http.Response _ok(Map<String, Object?> body) {
  return http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );
}
