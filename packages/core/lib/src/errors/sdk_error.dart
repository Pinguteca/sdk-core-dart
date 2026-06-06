// Copyright 2026 The Pinguteca SDK Authors.
//
// SdkError is the stable error type the SDK promises to keep across
// versions. Consumers catch this instead of package:connectrpc's
// ConnectException so the underlying transport can change (or pick up
// breaking upstream releases) without breaking caller code.

import 'dart:typed_data';

import 'package:connectrpc/connect.dart';

/// Status code on an [SdkError]. Re-exported from `package:connectrpc` so
/// consumers do not need to import the transport package to catch and
/// classify errors.
typedef SdkErrorCode = Code;

/// Stable typed boundary for RPC failures.
///
/// The SDK throws [SdkError] from every public surface (generated stubs,
/// L1.5 ergonomic wrappers, Layer 3 companions). Wraps a
/// [ConnectException] when one is available; for non-RPC failures (e.g. a
/// caller-side bug detected before the call leaves the SDK) build with
/// [SdkError.local].
final class SdkError implements Exception {
  /// Classification code. Mirrors the Connect / gRPC status taxonomy.
  final SdkErrorCode code;

  /// Human-readable message. Not stable across versions; useful for logs
  /// but never parse it programmatically.
  final String message;

  /// Underlying cause when one is available. Preserved so log pipelines can
  /// inspect the original transport exception without re-throwing it.
  final Object? cause;

  /// Server-supplied error details, e.g. `google.rpc.RetryInfo`,
  /// `google.rpc.BadRequest`. Carried as raw protobuf bytes; companion
  /// packages decode known types.
  final List<SdkErrorDetail> details;

  /// Response metadata (union of headers and trailers) attached to the
  /// failing call. Names are lowercased per HTTP convention.
  final Map<String, List<String>> metadata;

  SdkError._({
    required this.code,
    required this.message,
    required this.cause,
    required this.details,
    required this.metadata,
  });

  /// Builds an [SdkError] from a [ConnectException], preserving the code,
  /// message, cause, details, and metadata.
  factory SdkError.fromConnectException(ConnectException error) {
    return SdkError._(
      code: error.code,
      message: error.message,
      cause: error.cause ?? error,
      details: error.details
          .map((d) => SdkErrorDetail(d.type, d.value))
          .toList(growable: false),
      metadata: _collectMetadata(error.metadata),
    );
  }

  /// Builds an [SdkError] for a caller-side failure that never reached the
  /// wire (e.g. an invalid argument detected by an L1.5 helper).
  factory SdkError.local({
    required SdkErrorCode code,
    required String message,
    Object? cause,
  }) {
    return SdkError._(
      code: code,
      message: message,
      cause: cause,
      details: const [],
      metadata: const {},
    );
  }

  @override
  String toString() =>
      message.isNotEmpty ? '[${code.name}] $message' : '[${code.name}]';
}

/// Self-describing detail attached to an [SdkError]. The `type` is the
/// fully-qualified protobuf message name (e.g.
/// `type.googleapis.com/google.rpc.RetryInfo`); `value` is the wire bytes.
final class SdkErrorDetail {
  /// Fully-qualified protobuf type URL or short type path.
  final String type;

  /// Wire-format bytes of the detail message.
  final Uint8List value;

  /// Builds a detail entry.
  const SdkErrorDetail(this.type, this.value);
}

Map<String, List<String>> _collectMetadata(Headers headers) {
  final out = <String, List<String>>{};
  for (final entry in headers.entries) {
    final values = out[entry.name];
    if (values != null) {
      values.add(entry.value);
    } else {
      out[entry.name] = [entry.value];
    }
  }
  return out;
}
