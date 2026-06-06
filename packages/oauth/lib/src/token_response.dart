// Copyright 2026 The Pinguteca SDK Authors.
//
// Shared parsed view of an OAuth 2.0 token-endpoint response (RFC 6749
// §5.1). Used by every grant flow that calls the token endpoint.

import 'dart:convert';

import 'client_credentials.dart' show OAuthException;

/// Successful token-endpoint response.
final class TokenResponse {
  /// Bearer access token. Always present.
  final String accessToken;

  /// Refresh token, when the IdP issues one for this grant. Absent for
  /// `client_credentials` (the SDK acquires a fresh token instead) and
  /// often absent for `authorization_code` unless `offline_access` (or
  /// equivalent) was requested.
  final String? refreshToken;

  /// OpenID Connect ID token (a signed JWT). Present only when the
  /// `openid` scope was requested and the IdP issues one.
  final String? idToken;

  /// Lifetime of [accessToken]. Defaults to 1 hour when the IdP omits
  /// the `expires_in` field, matching most cloud IdPs.
  final Duration expiresIn;

  /// Granted scopes per the response. May be `null` when the IdP echoes
  /// the request scopes implicitly.
  final List<String>? scopes;

  /// Full token-endpoint response for fields the SDK does not model.
  final Map<String, dynamic> raw;

  /// Builds a token response from individual fields.
  const TokenResponse({
    required this.accessToken,
    required this.expiresIn,
    required this.raw,
    this.refreshToken,
    this.idToken,
    this.scopes,
  });

  /// Parses an HTTP token-endpoint body. Throws [OAuthException] when
  /// the body is non-JSON or missing the required `access_token` field.
  factory TokenResponse.fromBody(String body, {int? statusCode}) {
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(body) as Map<String, dynamic>;
    } on FormatException catch (error) {
      throw OAuthException(
        'token endpoint returned non-JSON body: $error',
        statusCode: statusCode,
        body: body,
      );
    }
    final accessToken = json['access_token'];
    if (accessToken is! String || accessToken.isEmpty) {
      throw OAuthException(
        'token endpoint response missing access_token',
        statusCode: statusCode,
        body: body,
      );
    }
    final expiresIn = json['expires_in'];
    final expirySeconds = switch (expiresIn) {
      final int v => v,
      final double v => v.toInt(),
      _ => 3600,
    };
    return TokenResponse(
      accessToken: accessToken,
      expiresIn: Duration(seconds: expirySeconds),
      refreshToken: _optionalString(json, 'refresh_token'),
      idToken: _optionalString(json, 'id_token'),
      scopes: _parseScope(json['scope']),
      raw: Map.unmodifiable(json),
    );
  }
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is String && value.isNotEmpty ? value : null;
}

List<String>? _parseScope(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return value.split(' ').where((s) => s.isNotEmpty).toList(growable: false);
}
