import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const expectedGeolocatorLine = '  geolocator: 14.0.1';

  test('geolocator stays pinned to the privacy-audited version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final matches = RegExp(
      r'^  geolocator:\s*(.+)$',
      multiLine: true,
    ).allMatches(pubspec).toList();

    expect(matches, hasLength(1));
    expect(matches.single.group(0), expectedGeolocatorLine);
  });

  test('resolved graph excludes Linux package_info chain but keeps Apple', () {
    final lockfile = File('pubspec.lock').readAsStringSync();

    expect(
      RegExp(r'^  geolocator_linux:$', multiLine: true).hasMatch(lockfile),
      isFalse,
    );
    expect(
      RegExp(r'^  package_info_plus:$', multiLine: true).hasMatch(lockfile),
      isFalse,
    );
    expect(
      RegExp(r'^  geolocator_apple:$', multiLine: true).hasMatch(lockfile),
      isTrue,
    );
  });

  test('tracked macOS registrant reflects the resolved privacy-safe graph', () {
    final registrant = File(
      'macos/Flutter/GeneratedPluginRegistrant.swift',
    ).readAsStringSync();

    expect(registrant.contains('GeolocatorPlugin'), isTrue);
    expect(registrant.contains('package_info_plus'), isFalse);
    expect(registrant.contains('FPPPackageInfoPlusPlugin'), isFalse);
  });

  test(
    'Runner does not claim an app privacy manifest without app-owned use',
    () {
      expect(File('ios/Runner/PrivacyInfo.xcprivacy').existsSync(), isFalse);

      final project = File(
        'ios/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();

      expect(project.contains('PrivacyInfo.xcprivacy'), isFalse);
    },
  );

  test('privacy audit keeps macOS archive validation as a release gate', () {
    final audit = File('IOS_PRIVACY_AUDIT.md').readAsStringSync();

    expect(
      audit.contains('MERZOX_RELEASE_IOS_PRIVACY_AUDIT_COMPLETE=true'),
      isTrue,
    );
    expect(audit.contains('macOS/Xcode'), isTrue);
    expect(audit.contains('iosPrivacyManifestAuditIncomplete'), isTrue);
    expect(audit.contains('package_info_plus'), isTrue);
    expect(audit.contains('`geolocator` to `14.0.1`'), isTrue);
  });
}
