// Copyright 2026 The Pinguteca SDK Authors.
//
// Extracts a server-supplied retry hint from a [ConnectException].
//
// Precedence per RFC 0006: a `google.rpc.RetryInfo` detail wins over a plain
// `retry-after` header because it is structured and the spec designates it
// for cross-protocol use. The caller-side cap is not applied to a
// server-supplied hint; the server speaks with more authority about its
// readiness than the client's local ceiling.

import 'dart:typed_data';

import 'package:connectrpc/connect.dart';

const _retryInfoTypePath = 'google.rpc.RetryInfo';
const _retryInfoFullUrl = 'type.googleapis.com/google.rpc.RetryInfo';
const _retryAfterHeader = 'retry-after';

/// Returns the server-supplied retry delay, or `null` if neither a
/// `RetryInfo` detail nor a parseable `retry-after` header is present.
Duration? retryHintFrom(ConnectException error) {
  for (final detail in error.details) {
    if (detail.type == _retryInfoTypePath || detail.type == _retryInfoFullUrl) {
      final d = _decodeRetryInfo(detail.value);
      if (d != null) {
        return d;
      }
    }
  }
  final header = error.metadata[_retryAfterHeader];
  if (header != null) {
    return _parseRetryAfter(header);
  }
  return null;
}

/// Decodes a `google.rpc.RetryInfo` wire-format payload. The message has a
/// single field, `Duration retry_delay = 1`. Returns null on malformed input
/// rather than throwing; the caller treats absence as "no hint" and falls
/// back to local backoff.
///
/// Hand-rolled rather than pulled in via the protobuf package so this module
/// keeps zero non-connectrpc dependencies and the wire reader stays inlined
/// for inspection.
Duration? _decodeRetryInfo(Uint8List bytes) {
  final reader = _WireReader(bytes);
  Duration? delay;
  while (reader.hasMore) {
    final tag = reader.readVarint();
    if (tag == null) return null;
    final fieldNumber = tag >> 3;
    final wireType = tag & 0x7;
    if (fieldNumber == 1 && wireType == 2) {
      final len = reader.readVarint();
      if (len == null) return null;
      final sub = reader.readBytes(len);
      if (sub == null) return null;
      delay = _decodeDuration(sub);
    } else {
      if (!reader.skip(wireType)) return null;
    }
  }
  return delay;
}

Duration? _decodeDuration(Uint8List bytes) {
  final reader = _WireReader(bytes);
  var seconds = 0;
  var nanos = 0;
  while (reader.hasMore) {
    final tag = reader.readVarint();
    if (tag == null) return null;
    final fieldNumber = tag >> 3;
    final wireType = tag & 0x7;
    if (fieldNumber == 1 && wireType == 0) {
      final v = reader.readVarint();
      if (v == null) return null;
      seconds = v;
    } else if (fieldNumber == 2 && wireType == 0) {
      final v = reader.readVarint();
      if (v == null) return null;
      nanos = v;
    } else {
      if (!reader.skip(wireType)) return null;
    }
  }
  return Duration(seconds: seconds, microseconds: nanos ~/ 1000);
}

/// Parses an HTTP `retry-after` header. Connect servers emit the
/// delta-seconds form per the HTTP spec; the HTTP-date form is not yet
/// supported (rare in RPC and would pull in a date parser).
Duration? _parseRetryAfter(String value) {
  final seconds = int.tryParse(value.trim());
  if (seconds == null || seconds < 0) return null;
  return Duration(seconds: seconds);
}

class _WireReader {
  _WireReader(this._bytes);

  final Uint8List _bytes;
  int _pos = 0;

  bool get hasMore => _pos < _bytes.length;

  /// Reads a varint up to 64 bits wide. Returns null on overflow or
  /// truncated input. The result is interpreted as an unsigned int, which
  /// is fine for the RetryInfo seconds/nanos fields we expect.
  int? readVarint() {
    var result = 0;
    var shift = 0;
    while (_pos < _bytes.length) {
      final b = _bytes[_pos++];
      result |= (b & 0x7F) << shift;
      if ((b & 0x80) == 0) {
        return result;
      }
      shift += 7;
      if (shift >= 64) return null;
    }
    return null;
  }

  Uint8List? readBytes(int len) {
    if (_pos + len > _bytes.length) return null;
    final out = Uint8List.sublistView(_bytes, _pos, _pos + len);
    _pos += len;
    return out;
  }

  /// Skips a field of the given wire type. Returns false on malformed input.
  bool skip(int wireType) {
    switch (wireType) {
      case 0:
        return readVarint() != null;
      case 1:
        return readBytes(8) != null;
      case 2:
        final len = readVarint();
        if (len == null) return false;
        return readBytes(len) != null;
      case 5:
        return readBytes(4) != null;
      default:
        return false;
    }
  }
}
