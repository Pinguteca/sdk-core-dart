// Copyright 2026 The Pinguteca SDK Authors.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sdk_core_dart_oauth/sdk_core_dart_oauth.dart';
import 'package:test/test.dart';

void main() {
  group('ClientCredentialsTokenSource', () {
    test('sends Basic auth header by default', () async {
      final captor = _RequestCaptor();
      final source = ClientCredentialsTokenSource(
        ClientCredentialsConfig(
          tokenEndpoint: Uri.parse('https://idp.example/oauth/token'),
          clientId: 'svc-1',
          clientSecret: 'sekret',
          httpClient: captor.client(
            _ok({'access_token': 'tok', 'expires_in': 3600}),
          ),
        ),
      );

      final token = await source.token();

      expect(token, 'tok');
      expect(
        captor.last!.headers['authorization'],
        'Basic ${base64Encode(utf8.encode('svc-1:sekret'))}',
      );
      expect(captor.last!.body, contains('grant_type=client_credentials'));
      expect(captor.last!.body, isNot(contains('client_id=')));
    });

    test('formPost mode puts credentials in the body', () async {
      final captor = _RequestCaptor();
      final source = ClientCredentialsTokenSource(
        ClientCredentialsConfig(
          tokenEndpoint: Uri.parse('https://idp.example/oauth/token'),
          clientId: 'svc-1',
          clientSecret: 'sekret',
          authMode: ClientAuthMode.formPost,
          httpClient: captor.client(_ok({'access_token': 'tok'})),
        ),
      );

      await source.token();

      expect(captor.last!.headers['authorization'], isNull);
      expect(captor.last!.body, contains('client_id=svc-1'));
      expect(captor.last!.body, contains('client_secret=sekret'));
    });

    test('includes scope when configured', () async {
      final captor = _RequestCaptor();
      final source = ClientCredentialsTokenSource(
        ClientCredentialsConfig(
          tokenEndpoint: Uri.parse('https://idp.example/oauth/token'),
          clientId: 'svc-1',
          clientSecret: 'sekret',
          scopes: const ['rpc.read', 'rpc.write'],
          httpClient: captor.client(_ok({'access_token': 'tok'})),
        ),
      );

      await source.token();

      // urlencoded space is '+'
      expect(captor.last!.body, contains('scope=rpc.read+rpc.write'));
    });

    test('caches the token across subsequent calls', () async {
      var hits = 0;
      final source = ClientCredentialsTokenSource(
        ClientCredentialsConfig(
          tokenEndpoint: Uri.parse('https://idp.example/oauth/token'),
          clientId: 'svc-1',
          clientSecret: 'sekret',
          httpClient: MockClient((req) async {
            hits++;
            return _ok({'access_token': 'tok-$hits', 'expires_in': 3600});
          }),
        ),
      );

      expect(await source.token(), 'tok-1');
      expect(await source.token(), 'tok-1');
      expect(await source.token(), 'tok-1');
      expect(hits, 1);
    });

    test('refreshes when the cached token is past earlyRefresh', () async {
      var hits = 0;
      var now = DateTime.utc(2026, 1, 1);
      final source = ClientCredentialsTokenSource(
        ClientCredentialsConfig(
          tokenEndpoint: Uri.parse('https://idp.example/oauth/token'),
          clientId: 'svc-1',
          clientSecret: 'sekret',
          earlyRefresh: const Duration(seconds: 60),
          now: () => now,
          httpClient: MockClient((req) async {
            hits++;
            return _ok({'access_token': 'tok-$hits', 'expires_in': 120});
          }),
        ),
      );

      expect(await source.token(), 'tok-1');
      // Inside the cache window.
      now = now.add(const Duration(seconds: 30));
      expect(await source.token(), 'tok-1');
      // Past the earlyRefresh boundary: refresh.
      now = now.add(const Duration(seconds: 35));
      expect(await source.token(), 'tok-2');
      expect(hits, 2);
    });

    test('deduplicates concurrent refreshes (single-flight)', () async {
      var hits = 0;
      final gate = Completer<void>();
      final source = ClientCredentialsTokenSource(
        ClientCredentialsConfig(
          tokenEndpoint: Uri.parse('https://idp.example/oauth/token'),
          clientId: 'svc-1',
          clientSecret: 'sekret',
          httpClient: MockClient((req) async {
            hits++;
            await gate.future;
            return _ok({'access_token': 'tok-$hits', 'expires_in': 3600});
          }),
        ),
      );

      // Two concurrent token() calls during the first refresh.
      final a = source.token();
      final b = source.token();
      gate.complete();
      final results = await Future.wait([a, b]);

      expect(results, ['tok-1', 'tok-1']);
      expect(hits, 1);
    });

    test('throws OAuthException on non-2xx responses', () async {
      final source = ClientCredentialsTokenSource(
        ClientCredentialsConfig(
          tokenEndpoint: Uri.parse('https://idp.example/oauth/token'),
          clientId: 'svc-1',
          clientSecret: 'sekret',
          httpClient: MockClient((req) async {
            return http.Response(
              jsonEncode({'error': 'invalid_client'}),
              401,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );

      await expectLater(
        source.token(),
        throwsA(
          isA<OAuthException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.body, 'body', contains('invalid_client')),
        ),
      );
    });

    test('throws OAuthException when access_token is missing', () async {
      final source = ClientCredentialsTokenSource(
        ClientCredentialsConfig(
          tokenEndpoint: Uri.parse('https://idp.example/oauth/token'),
          clientId: 'svc-1',
          clientSecret: 'sekret',
          httpClient: MockClient((req) async {
            return _ok({'expires_in': 3600});
          }),
        ),
      );

      await expectLater(source.token(), throwsA(isA<OAuthException>()));
    });

    test('defaults expiry to 3600s when expires_in is missing', () async {
      var now = DateTime.utc(2026, 1, 1);
      var hits = 0;
      final source = ClientCredentialsTokenSource(
        ClientCredentialsConfig(
          tokenEndpoint: Uri.parse('https://idp.example/oauth/token'),
          clientId: 'svc-1',
          clientSecret: 'sekret',
          earlyRefresh: const Duration(seconds: 60),
          now: () => now,
          httpClient: MockClient((req) async {
            hits++;
            return _ok({'access_token': 'tok-$hits'});
          }),
        ),
      );

      await source.token();
      // Advance 50 minutes; still inside 1h - 60s window.
      now = now.add(const Duration(minutes: 50));
      await source.token();
      expect(hits, 1);
    });
  });
}

class _RequestCaptor {
  http.Request? last;

  http.Client client(http.Response response) {
    return MockClient((req) async {
      last = req;
      return response;
    });
  }
}

http.Response _ok(Map<String, Object?> body) {
  return http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );
}
