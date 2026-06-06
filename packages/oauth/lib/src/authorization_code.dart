// Copyright 2026 The Pinguteca SDK Authors.
//
// OAuth 2.0 authorization_code grant (RFC 6749 §4.1) with PKCE
// (RFC 7636). The SDK supplies the protocol primitives - URL building,
// code exchange, refresh-token rotation - but stays out of the
// platform-specific browser interaction. The caller drives the user
// agent (launch URL, listen on a localhost redirect, capture the code)
// and hands the code back to [AuthorizationCodeFlow.exchange].

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sdk_core_dart/auth.dart' show TokenSource;

import 'client_credentials.dart' show ClientAuthMode, OAuthException;
import 'oidc_discovery.dart';
import 'pkce.dart';
import 'token_response.dart';

/// Configuration for [AuthorizationCodeFlow].
final class AuthorizationCodeConfig {
  /// IdP's authorization endpoint (HTML/JS user-agent flow lands here).
  final Uri authorizationEndpoint;

  /// IdP's token endpoint (code-for-token exchange POSTs land here).
  final Uri tokenEndpoint;

  /// OAuth client identifier issued by the IdP.
  final String clientId;

  /// Client secret. `null` for public clients (mobile, SPA, desktop
  /// without backend). When present, the secret is sent during code
  /// exchange per [ClientAuthMode].
  final String? clientSecret;

  /// Redirect URI registered with the IdP. The user agent lands here
  /// with the authorization code in the query string.
  final Uri redirectUri;

  /// Requested scopes. Most IdPs require at least `openid` to issue an
  /// ID token; `offline_access` (or vendor equivalent) is required to
  /// receive a refresh token.
  final List<String>? scopes;

  /// How a [clientSecret] is sent during code exchange and refresh. No
  /// effect when [clientSecret] is `null`.
  final ClientAuthMode clientAuthMode;

  /// Lead time before [TokenResponse.expiresIn] when refresh fires.
  /// Defaults to 60 seconds to absorb clock skew.
  final Duration earlyRefresh;

  /// HTTP client used for code exchange and refresh. Defaults to a
  /// fresh `http.Client()`.
  final http.Client? httpClient;

  /// Clock source. Tests inject a controllable clock.
  final DateTime Function()? now;

  /// Builds a config.
  const AuthorizationCodeConfig({
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    required this.clientId,
    required this.redirectUri,
    this.clientSecret,
    this.scopes,
    this.clientAuthMode = ClientAuthMode.basic,
    this.earlyRefresh = const Duration(seconds: 60),
    this.httpClient,
    this.now,
  });
}

/// Protocol primitives for the authorization_code + PKCE flow.
final class AuthorizationCodeFlow {
  /// Builds a flow against [config].
  const AuthorizationCodeFlow(this.config);

  /// Configuration for this flow.
  final AuthorizationCodeConfig config;

  /// Discovers IdP metadata for [issuer] and returns a flow wired to
  /// the discovered authorization/token endpoints.
  static Future<AuthorizationCodeFlow> fromIssuer({
    required Uri issuer,
    required String clientId,
    required Uri redirectUri,
    String? clientSecret,
    List<String>? scopes,
    ClientAuthMode clientAuthMode = ClientAuthMode.basic,
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
    final authEndpoint = metadata.authorizationEndpoint;
    if (authEndpoint == null) {
      throw OAuthException(
        'OIDC discovery did not advertise an authorization_endpoint; '
        'the IdP does not support authorization_code at $issuer',
      );
    }
    return AuthorizationCodeFlow(
      AuthorizationCodeConfig(
        authorizationEndpoint: authEndpoint,
        tokenEndpoint: metadata.tokenEndpoint,
        clientId: clientId,
        clientSecret: clientSecret,
        redirectUri: redirectUri,
        scopes: scopes,
        clientAuthMode: clientAuthMode,
        earlyRefresh: earlyRefresh,
        httpClient: httpClient,
        now: now,
      ),
    );
  }

  /// Builds the URL to send the user agent to.
  ///
  /// [state] is the CSRF token: the caller generates it, persists it
  /// across the round trip, and asserts the redirect URL echoes it
  /// before calling [exchange]. [pkce] binds this authorization to the
  /// later code exchange. [nonce] is optional but recommended when the
  /// IdP issues ID tokens. [extraParams] propagate vendor extensions
  /// (e.g. `prompt=consent`, `audience=...`).
  Uri buildAuthorizationUrl({
    required String state,
    required PkcePair pkce,
    String? nonce,
    Map<String, String>? extraParams,
  }) {
    final params = <String, String>{
      'response_type': 'code',
      'client_id': config.clientId,
      'redirect_uri': config.redirectUri.toString(),
      'state': state,
      'code_challenge': pkce.codeChallenge,
      'code_challenge_method': pkce.codeChallengeMethod,
    };
    final scopes = config.scopes;
    if (scopes != null && scopes.isNotEmpty) {
      params['scope'] = scopes.join(' ');
    }
    if (nonce != null) {
      params['nonce'] = nonce;
    }
    if (extraParams != null) {
      params.addAll(extraParams);
    }

    final existing = Map<String, String>.from(
      config.authorizationEndpoint.queryParameters,
    );
    existing.addAll(params);
    return config.authorizationEndpoint.replace(queryParameters: existing);
  }

  /// Exchanges an authorization [code] (returned to the redirect URI)
  /// for a [TokenResponse]. [codeVerifier] is the PKCE verifier that
  /// matched [PkcePair.codeChallenge] in [buildAuthorizationUrl].
  Future<TokenResponse> exchange({
    required String code,
    required String codeVerifier,
  }) {
    return _post(<String, String>{
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': config.redirectUri.toString(),
      'code_verifier': codeVerifier,
    });
  }

  /// Refreshes an access token using a previously-issued refresh token.
  /// Returns a fresh [TokenResponse]; many IdPs rotate the refresh
  /// token on every call, so callers should adopt the new one.
  Future<TokenResponse> refresh({required String refreshToken}) {
    final body = <String, String>{
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
    };
    final scopes = config.scopes;
    if (scopes != null && scopes.isNotEmpty) {
      body['scope'] = scopes.join(' ');
    }
    return _post(body);
  }

  Future<TokenResponse> _post(Map<String, String> body) async {
    final client = config.httpClient ?? http.Client();
    final headers = <String, String>{
      'content-type': 'application/x-www-form-urlencoded',
      'accept': 'application/json',
    };

    final secret = config.clientSecret;
    switch (config.clientAuthMode) {
      case ClientAuthMode.mtls:
        // RFC 8705: TLS handshake authenticates; client_id only.
        body['client_id'] = config.clientId;
        break;
      case ClientAuthMode.basic:
        if (secret == null) {
          body['client_id'] = config.clientId;
        } else {
          headers['authorization'] =
              'Basic ${_basicAuth(config.clientId, secret)}';
        }
        break;
      case ClientAuthMode.formPost:
        body['client_id'] = config.clientId;
        if (secret != null) {
          body['client_secret'] = secret;
        }
        break;
    }

    final http.Response response;
    try {
      response = await client.post(
        config.tokenEndpoint,
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
    return TokenResponse.fromBody(
      response.body,
      statusCode: response.statusCode,
    );
  }
}

/// [TokenSource] backed by an authorization_code grant's refresh token.
///
/// Construct via [AuthorizationCodeTokenSource.fromInitial] once the
/// caller has driven the user-agent flow and obtained a [TokenResponse]
/// from [AuthorizationCodeFlow.exchange]. The source caches the access
/// token, refreshes when the cached value is past
/// [AuthorizationCodeConfig.earlyRefresh] before expiry, and rotates
/// the refresh token whenever the IdP returns a new one.
///
/// Concurrent [token] calls during a refresh share the in-flight
/// future; the IdP never sees duplicate refresh traffic.
final class AuthorizationCodeTokenSource implements TokenSource {
  AuthorizationCodeTokenSource._({
    required AuthorizationCodeFlow flow,
    required TokenResponse initial,
  }) : _flow = flow,
       _accessToken = initial.accessToken,
       _refreshToken = initial.refreshToken,
       _expiresAt = (flow.config.now ?? DateTime.now)().add(initial.expiresIn);

  /// Builds a source from an [initial] token response.
  ///
  /// Throws [ArgumentError] when [initial.refreshToken] is `null`: this
  /// source maintains the access token across refreshes, so a refresh
  /// token is mandatory. For flows that issue only an access token (no
  /// refresh), call [AuthorizationCodeFlow.exchange] manually each time
  /// instead of using a `TokenSource`.
  factory AuthorizationCodeTokenSource.fromInitial({
    required AuthorizationCodeFlow flow,
    required TokenResponse initial,
  }) {
    if (initial.refreshToken == null) {
      throw ArgumentError.value(
        initial,
        'initial',
        'refresh_token is required; the IdP did not issue one. Request '
            'offline_access (or vendor equivalent) on the authorization '
            'request, or invoke flow.exchange manually per call.',
      );
    }
    return AuthorizationCodeTokenSource._(flow: flow, initial: initial);
  }

  final AuthorizationCodeFlow _flow;

  String _accessToken;
  String? _refreshToken;
  DateTime _expiresAt;
  Future<String>? _inFlight;

  /// Current refresh token. Exposed so callers can persist it across
  /// process restarts.
  String? get refreshToken => _refreshToken;

  /// Current access-token expiry. Exposed for diagnostics.
  DateTime get expiresAt => _expiresAt;

  @override
  Future<String> token() {
    final now = (_flow.config.now ?? DateTime.now)();
    if (_expiresAt.isAfter(now.add(_flow.config.earlyRefresh))) {
      return Future.value(_accessToken);
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
    final refresh = _refreshToken;
    if (refresh == null) {
      throw const OAuthException(
        'no refresh token available; the source cannot recover',
      );
    }
    final response = await _flow.refresh(refreshToken: refresh);
    _accessToken = response.accessToken;
    if (response.refreshToken != null) {
      _refreshToken = response.refreshToken;
    }
    final issuedAt = (_flow.config.now ?? DateTime.now)();
    _expiresAt = issuedAt.add(response.expiresIn);
    return _accessToken;
  }
}

String _basicAuth(String id, String secret) {
  return base64Encode(utf8.encode('$id:$secret'));
}
