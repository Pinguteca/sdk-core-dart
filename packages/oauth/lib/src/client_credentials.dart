// Copyright 2026 The Pinguteca SDK Authors.
//
// OAuth 2.0 client_credentials grant flow (RFC 6749 §4.4) as a TokenSource
// the L2 auth interceptor can consume.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sdk_core_dart/auth.dart' show TokenSource;

import 'oidc_discovery.dart';

/// Where the client credentials are sent on the token request.
enum ClientAuthMode {
  /// `Authorization: Basic base64(clientId:clientSecret)` header. Default
  /// per RFC 6749 §2.3.1 and required by most IdPs (Auth0, Entra ID,
  /// Keycloak default config).
  basic,

  /// Credentials in the `application/x-www-form-urlencoded` body as
  /// `client_id` and `client_secret`. Use only when the IdP rejects
  /// Basic auth or documents form-post as the supported mode.
  formPost,

  /// Mutual-TLS client authentication per RFC 8705. The TLS handshake
  /// authenticates the client; no Basic auth header or `client_secret`
  /// body field is sent. The configured `httpClient` MUST present the
  /// client certificate during the handshake (see
  /// `package:sdk_core_dart_oauth/mtls.dart`). `client_id` still
  /// appears in the body so the IdP can pick the correct policy.
  mtls,
}

/// Configuration for [ClientCredentialsTokenSource].
final class ClientCredentialsConfig {
  /// The IdP's token endpoint. Typically discovered from
  /// `.well-known/openid-configuration` but supplied directly here.
  final Uri tokenEndpoint;

  /// OAuth client identifier issued by the IdP.
  final String clientId;

  /// OAuth client secret. Treat as a credential: store via your secret
  /// manager, never check into source control.
  final String clientSecret;

  /// Optional space-delimited scopes to request. Most IdPs require this;
  /// some default to all-scopes when omitted.
  final List<String>? scopes;

  /// Whether to authenticate with HTTP Basic or POST-body credentials.
  /// Defaults to [ClientAuthMode.basic].
  final ClientAuthMode authMode;

  /// Refresh the cached token this many seconds before the
  /// `expires_in` deadline. Defaults to 60 seconds, which absorbs
  /// reasonable clock skew without burning many extra token calls.
  final Duration earlyRefresh;

  /// HTTP client used to contact the token endpoint. Defaults to a fresh
  /// `http.Client()`; inject in tests or to share a connection pool with
  /// the rest of the application.
  final http.Client? httpClient;

  /// Clock source. Tests inject a controllable clock to validate the
  /// expiry-aware refresh window.
  final DateTime Function()? now;

  /// Builds a config with the recommended defaults.
  const ClientCredentialsConfig({
    required this.tokenEndpoint,
    required this.clientId,
    required this.clientSecret,
    this.scopes,
    this.authMode = ClientAuthMode.basic,
    this.earlyRefresh = const Duration(seconds: 60),
    this.httpClient,
    this.now,
  });
}

/// Token-endpoint failure. Carries the HTTP status code and the response
/// body so callers can decode RFC 6749 §5.2 error fields when needed.
final class OAuthException implements Exception {
  /// Short human-readable message; not stable across versions.
  final String message;

  /// HTTP status code returned by the token endpoint, or `null` if the
  /// failure was transport-level.
  final int? statusCode;

  /// Raw response body, or `null` if no body was received.
  final String? body;

  /// Builds an exception with the given details.
  const OAuthException(this.message, {this.statusCode, this.body});

  @override
  String toString() {
    final code = statusCode != null ? ' [$statusCode]' : '';
    return 'OAuthException$code: $message';
  }
}

/// [TokenSource] backed by the OAuth 2.0 client_credentials grant flow.
///
/// Behaviour:
/// - First call hits the token endpoint, caches the access token, and
///   records the expiry derived from `expires_in`.
/// - Subsequent calls return the cached token until the expiry minus
///   [ClientCredentialsConfig.earlyRefresh] has elapsed.
/// - Concurrent [token] invocations during a refresh share the single
///   in-flight request; the IdP never sees duplicate refresh traffic.
/// - HTTP or parsing failures throw [OAuthException] without poisoning
///   the cache: a previously-good token stays usable on the next call.
final class ClientCredentialsTokenSource implements TokenSource {
  /// Builds a source using [config].
  ClientCredentialsTokenSource(this._config);

  /// Convenience factory that performs OIDC discovery on [issuer] and
  /// returns a [ClientCredentialsTokenSource] wired to the resulting
  /// `token_endpoint`. Discovery happens once at construction; subsequent
  /// [token] calls reuse the resolved endpoint.
  static Future<ClientCredentialsTokenSource> fromIssuer({
    required Uri issuer,
    required String clientId,
    required String clientSecret,
    List<String>? scopes,
    ClientAuthMode authMode = ClientAuthMode.basic,
    Duration earlyRefresh = const Duration(seconds: 60),
    http.Client? httpClient,
    DateTime Function()? now,
    Duration discoveryTimeout = const Duration(seconds: 10),
    bool validateIssuer = true,
  }) async {
    final metadata = await discoverOidc(
      OidcDiscoveryConfig(
        issuer: issuer,
        httpClient: httpClient,
        timeout: discoveryTimeout,
        validateIssuer: validateIssuer,
      ),
    );
    return ClientCredentialsTokenSource(
      ClientCredentialsConfig(
        tokenEndpoint: metadata.tokenEndpoint,
        clientId: clientId,
        clientSecret: clientSecret,
        scopes: scopes,
        authMode: authMode,
        earlyRefresh: earlyRefresh,
        httpClient: httpClient,
        now: now,
      ),
    );
  }

  final ClientCredentialsConfig _config;

  String? _cached;
  DateTime? _expiresAt;
  Future<String>? _inFlight;

  @override
  Future<String> token() {
    final now = (_config.now ?? DateTime.now)();
    final cached = _cached;
    final expiresAt = _expiresAt;
    if (cached != null &&
        expiresAt != null &&
        expiresAt.isAfter(now.add(_config.earlyRefresh))) {
      return Future.value(cached);
    }
    final pending = _inFlight;
    if (pending != null) {
      return pending;
    }
    final fresh = _refresh();
    _inFlight = fresh;
    return fresh.whenComplete(() {
      if (identical(_inFlight, fresh)) {
        _inFlight = null;
      }
    });
  }

  Future<String> _refresh() async {
    final client = _config.httpClient ?? http.Client();
    final body = <String, String>{'grant_type': 'client_credentials'};
    final scopes = _config.scopes;
    if (scopes != null && scopes.isNotEmpty) {
      body['scope'] = scopes.join(' ');
    }
    final headers = <String, String>{
      'content-type': 'application/x-www-form-urlencoded',
      'accept': 'application/json',
    };
    switch (_config.authMode) {
      case ClientAuthMode.basic:
        final credentials = base64Encode(
          utf8.encode('${_config.clientId}:${_config.clientSecret}'),
        );
        headers['authorization'] = 'Basic $credentials';
        break;
      case ClientAuthMode.formPost:
        body['client_id'] = _config.clientId;
        body['client_secret'] = _config.clientSecret;
        break;
      case ClientAuthMode.mtls:
        // RFC 8705: TLS handshake authenticates; client_id only.
        body['client_id'] = _config.clientId;
        break;
    }

    final http.Response response;
    try {
      response = await client.post(
        _config.tokenEndpoint,
        headers: headers,
        body: body,
      );
    } on Exception catch (error) {
      throw OAuthException('token endpoint request failed: $error');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OAuthException(
        'token endpoint returned non-2xx',
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException catch (error) {
      throw OAuthException(
        'token endpoint returned non-JSON body: $error',
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    final accessToken = json['access_token'];
    if (accessToken is! String || accessToken.isEmpty) {
      throw OAuthException(
        'token endpoint response missing access_token',
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    final expiresIn = json['expires_in'];
    final expirySeconds = switch (expiresIn) {
      final int v => v,
      final double v => v.toInt(),
      _ => 3600,
    };

    final issuedAt = (_config.now ?? DateTime.now)();
    _cached = accessToken;
    _expiresAt = issuedAt.add(Duration(seconds: expirySeconds));
    return accessToken;
  }
}
