// Copyright 2026 The Pinguteca SDK Authors.
//
// OpenID Connect Discovery 1.0 / RFC 8414 implementation. Fetches an
// issuer's `.well-known/openid-configuration` document and returns the
// fields the OAuth companion cares about. Callers configure only the
// issuer URL; endpoint URLs come from the discovery document.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'client_credentials.dart' show OAuthException;

/// Path appended to the issuer URL when fetching the OIDC metadata
/// document. RFC 8414 §3 mandates the exact path; do not parameterise.
const _wellKnownPath = '.well-known/openid-configuration';

/// Configuration for [discoverOidc].
final class OidcDiscoveryConfig {
  /// Issuer base URL. The discovery document is fetched from
  /// `<issuer>/.well-known/openid-configuration`. A trailing slash on
  /// the issuer is tolerated; the helper joins paths safely.
  final Uri issuer;

  /// HTTP client used to fetch the document. Defaults to a fresh
  /// `http.Client()`.
  final http.Client? httpClient;

  /// Maximum time to wait for the discovery document before failing.
  /// Defaults to 10 seconds.
  final Duration timeout;

  /// When true (default), require the `issuer` field in the response to
  /// match the requested issuer URL exactly (RFC 8414 §3.3). Disable
  /// only when interoperating with a misconfigured IdP and the risk is
  /// accepted in writing.
  final bool validateIssuer;

  /// Builds a config with the recommended defaults.
  const OidcDiscoveryConfig({
    required this.issuer,
    this.httpClient,
    this.timeout = const Duration(seconds: 10),
    this.validateIssuer = true,
  });
}

/// Subset of the OIDC discovery / RFC 8414 metadata the SDK consumes.
/// Additional fields the IdP returns are preserved in [raw] so callers
/// can read them without re-fetching.
final class OidcMetadata {
  /// Echo of the `issuer` claim from the discovery document.
  final Uri issuer;

  /// `token_endpoint` URL. Required.
  final Uri tokenEndpoint;

  /// `authorization_endpoint` URL. Required for `authorization_code` /
  /// PKCE flows; `null` when the IdP only supports `client_credentials`.
  final Uri? authorizationEndpoint;

  /// `jwks_uri` URL when published. Useful for verifying tokens locally
  /// when the SDK gains a JWT verifier.
  final Uri? jwksUri;

  /// `grant_types_supported`. May be `null` if the IdP omits the field
  /// (RFC 8414 says callers must assume only `authorization_code` and
  /// `implicit` are supported when missing).
  final List<String>? grantTypesSupported;

  /// `token_endpoint_auth_methods_supported`. Tells callers which
  /// [ClientAuthMode] values the IdP accepts.
  final List<String>? tokenEndpointAuthMethodsSupported;

  /// `scopes_supported`. Empty when the IdP does not advertise scopes.
  final List<String>? scopesSupported;

  /// Full discovery document for fields the SDK does not model.
  final Map<String, dynamic> raw;

  /// Builds a metadata instance.
  const OidcMetadata({
    required this.issuer,
    required this.tokenEndpoint,
    required this.raw,
    this.authorizationEndpoint,
    this.jwksUri,
    this.grantTypesSupported,
    this.tokenEndpointAuthMethodsSupported,
    this.scopesSupported,
  });
}

/// Fetches and parses the OIDC discovery document for the configured
/// issuer. Throws [OAuthException] on transport, status, or schema
/// failures.
Future<OidcMetadata> discoverOidc(OidcDiscoveryConfig config) async {
  final url = _wellKnownUrl(config.issuer);
  final client = config.httpClient ?? http.Client();

  final http.Response response;
  try {
    response = await client
        .get(url, headers: const {'accept': 'application/json'})
        .timeout(config.timeout);
  } on TimeoutException catch (error) {
    throw OAuthException('OIDC discovery timed out: $error');
  } on Exception catch (error) {
    throw OAuthException('OIDC discovery request failed: $error');
  }

  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw OAuthException(
      'OIDC discovery returned non-2xx',
      statusCode: response.statusCode,
      body: response.body,
    );
  }

  final Map<String, dynamic> json;
  try {
    json = jsonDecode(response.body) as Map<String, dynamic>;
  } on FormatException catch (error) {
    throw OAuthException(
      'OIDC discovery returned non-JSON: $error',
      statusCode: response.statusCode,
      body: response.body,
    );
  }

  final issuerClaim = _requireString(json, 'issuer');
  final tokenEndpoint = _requireString(json, 'token_endpoint');

  if (config.validateIssuer) {
    final expected = _normaliseIssuer(config.issuer);
    if (_normaliseIssuer(Uri.parse(issuerClaim)) != expected) {
      throw OAuthException(
        'OIDC discovery issuer mismatch: expected $expected, got $issuerClaim',
        statusCode: response.statusCode,
        body: response.body,
      );
    }
  }

  return OidcMetadata(
    issuer: Uri.parse(issuerClaim),
    tokenEndpoint: Uri.parse(tokenEndpoint),
    authorizationEndpoint: _optionalUri(json, 'authorization_endpoint'),
    jwksUri: _optionalUri(json, 'jwks_uri'),
    grantTypesSupported: _optionalStringList(json, 'grant_types_supported'),
    tokenEndpointAuthMethodsSupported: _optionalStringList(
      json,
      'token_endpoint_auth_methods_supported',
    ),
    scopesSupported: _optionalStringList(json, 'scopes_supported'),
    raw: Map.unmodifiable(json),
  );
}

Uri _wellKnownUrl(Uri issuer) {
  final segments = List<String>.from(issuer.pathSegments)
    ..removeWhere((s) => s.isEmpty);
  return issuer.replace(
    pathSegments: [...segments, ..._wellKnownPath.split('/')],
  );
}

String _normaliseIssuer(Uri issuer) {
  final segments = List<String>.from(issuer.pathSegments)
    ..removeWhere((s) => s.isEmpty);
  return issuer
      .replace(pathSegments: segments, query: '', fragment: '')
      .toString();
}

String _requireString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw OAuthException(
      'OIDC discovery response missing required field "$key"',
      body: jsonEncode(json),
    );
  }
  return value;
}

Uri? _optionalUri(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) return null;
  return Uri.tryParse(value);
}

List<String>? _optionalStringList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List) return null;
  return [
    for (final v in value)
      if (v is String) v,
  ];
}
