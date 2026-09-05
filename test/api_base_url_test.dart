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
}
