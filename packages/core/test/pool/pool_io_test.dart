// Copyright 2026 The Pinguteca SDK Authors.
//
// Tests run on the Dart VM so we exercise the dart:io implementation
// directly. The web stub is verified by analyzer (it must compile and
// throw on use); a full web test harness is out of scope for L2.

@TestOn('vm')
library;

import 'package:sdk_core_dart/pool.dart';
import 'package:sdk_core_dart/src/pool/pool_io.dart';
import 'package:test/test.dart';

void main() {
  group('buildIoHttpClient', () {
    test('applies defaults from ConnectionPoolConfig', () {
      final client = buildIoHttpClient();
      try {
        expect(client.maxConnectionsPerHost, 50);
        expect(client.idleTimeout, const Duration(seconds: 90));
        expect(client.connectionTimeout, const Duration(seconds: 10));
      } finally {
        client.close(force: true);
      }
    });

    test('honours every override', () {
      final client = buildIoHttpClient(
        const ConnectionPoolConfig(
          maxConnectionsPerHost: 8,
          idleTimeout: Duration(seconds: 30),
          connectionTimeout: Duration(seconds: 3),
          userAgent: 'sdk-test/1.0',
        ),
      );
      try {
        expect(client.maxConnectionsPerHost, 8);
        expect(client.idleTimeout, const Duration(seconds: 30));
        expect(client.connectionTimeout, const Duration(seconds: 3));
        expect(client.userAgent, 'sdk-test/1.0');
      } finally {
        client.close(force: true);
      }
    });

    test('leaves connectionTimeout unset when config supplies null', () {
      final client = buildIoHttpClient(
        const ConnectionPoolConfig(connectionTimeout: null),
      );
      try {
        expect(client.connectionTimeout, isNull);
      } finally {
        client.close(force: true);
      }
    });
  });

  group('pooledHttp1Client', () {
    test('returns a non-null Connect HttpClient function', () {
      final client = pooledHttp1Client();
      expect(client, isNotNull);
    });
  });
}
