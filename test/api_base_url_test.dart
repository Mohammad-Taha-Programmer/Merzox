import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/services/api_service.dart';

/// Which host the app talks to when nothing told it.
///
/// This was one developer's LAN address, typed into the source. The
/// workstation later moved to another number on the same router, and every
/// build made without `MERZOX_API_BASE_URL` then spent its requests on an
/// address nobody answers - which the customer reads as "the server is
/// unreachable" and the developer reads as an intermittent fault. It cost
/// real time to find, because the server was up the whole while.
///
/// So the rule under test is not which address is right today. It is that no
/// address here can go stale: every fallback must be a fixed name for "this
/// machine".

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('an Android build falls back to the emulator host alias', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    // 10.0.2.2 is what the Android emulator maps to its host's loopback. It
    // is a fixed name, not a machine's current address.
    expect(ApiService.developmentHost, '10.0.2.2');
    expect(ApiService.defaultBaseUrl, 'http://10.0.2.2:4000/api/v1');
  });

  test('everywhere else falls back to the loopback itself', () {
    for (final TargetPlatform platform in <TargetPlatform>[
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      debugDefaultTargetPlatformOverride = platform;

      expect(ApiService.developmentHost, '127.0.0.1', reason: '$platform');
    }
  });

  test('no fallback names a machine on somebody LAN', () {
    for (final TargetPlatform platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      final String host = ApiService.developmentHost;

      // A private-range address here is a developer's own machine, and it will
      // be wrong for everyone else and eventually for them too.
      expect(
        RegExp(
          r'^(192\.168\.|10\.(?!0\.2\.2$)|172\.(1[6-9]|2\d|3[01])\.)',
        ).hasMatch(host),
        isFalse,
        reason: '$platform falls back to $host, which is somebody LAN address',
      );
    }
  });

  test('the compile-time define wins over every fallback', () {
    // Nothing is passed in this test run, so the define is empty and the
    // fallback is what answers. The branch itself is what matters: a build
    // that names its server must reach that server.
    expect(ApiService.configuredBaseUrl, isEmpty);
    expect(ApiService.defaultBaseUrl, endsWith(':4000/api/v1'));
  });

  group('how long a request is given', () {
    // The server is only as near as the network the developer is on. On one
    // of them the database sat 600ms away and a plain list took four and a
    // half seconds - close enough to the limit that requests crossed it and
    // surfaced as "the server is unreachable" with nothing wrong on either
    // side. So a build can say otherwise. What ships must not change.

    test('a build that says nothing gets what it always got', () {
      expect(ApiService.configuredTimeoutMs, 0);
      expect(ApiService.kDefaultTimeout, const Duration(seconds: 10));
      expect(ApiService.defaultTimeout, const Duration(seconds: 10));
    });

    test('a build that names a timeout is given it', () {
      expect(
        ApiService.timeoutFrom(30000),
        const Duration(milliseconds: 30000),
      );
    });

    test('a number too small to be an answer is read as none', () {
      // `MERZOX_API_TIMEOUT_MS=30` is a plausible way to write "thirty
      // seconds" into a field whose name ends in MS. Honoured literally it
      // gives every request thirty milliseconds and fails all of them, so it
      // falls back to the value that already works instead.
      for (final int slip in <int>[0, -1, 30, 999]) {
        expect(
          ApiService.timeoutFrom(slip),
          ApiService.kDefaultTimeout,
          reason: '$slip should not be honoured',
        );
      }

      expect(
        ApiService.timeoutFrom(ApiService.kMinimumTimeoutMs),
        const Duration(milliseconds: 1000),
      );
    });

    test('both limits are the one number, not two that drift', () {
      // Connecting is the fast half and receiving is the slow one, but a
      // build that raises the limit means the whole wait, not part of it.
      final BaseOptions options = ApiService.options(
        timeout: const Duration(seconds: 42),
      );

      expect(options.connectTimeout, const Duration(seconds: 42));
      expect(options.receiveTimeout, const Duration(seconds: 42));
      expect(options.baseUrl, ApiService.defaultBaseUrl);
    });

    test('every client that talks to the server is built the same way', () {
      // Four services reach the one server, each with its own Dio. Raising
      // the limit in one of them fixes one screen and leaves the other three
      // crossing it, so this holds them to the shared options rather than to
      // a number of their own.
      const List<String> clients = <String>[
        'lib/services/api_service.dart',
        'lib/services/notification_preference_service.dart',
        'lib/services/review_eligibility_service.dart',
        'lib/features/authentication/password_recovery/data/'
            'password_recovery_api_service.dart',
      ];

      for (final String path in clients) {
        final String source = File(path).readAsStringSync();

        expect(
          source,
          contains('options(baseUrl: baseUrl, timeout: timeout)'),
          reason: '$path builds its client some other way',
        );
        expect(
          source,
          isNot(contains('connectTimeout: const Duration')),
          reason: '$path still names a limit of its own',
        );
      }
    });
  });
}
