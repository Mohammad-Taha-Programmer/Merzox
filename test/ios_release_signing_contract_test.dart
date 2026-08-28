import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/config/release_readiness.dart';
import 'package:merzox/core/config/release_readiness_repository.dart';

void main() {
  test('canonical iOS project satisfies repository signing structure', () {
    final snapshot = ReleaseReadinessRepositoryScanner(
      environment: const {},
    ).scan();

    expect(snapshot.iosProductionSigningConfigReady, isTrue);
    expect(snapshot.input.iosProductionSigningReady, isFalse);

    expect(
      snapshot.readiness.blockers,
      contains(ReleaseReadinessBlocker.iosProductionSigningMissing),
    );
  });

  test('iOS signing activation requires external attestation', () {
    final snapshot = ReleaseReadinessRepositoryScanner(
      environment: const {'MERZOX_RELEASE_IOS_SIGNING_READY': 'true'},
    ).scan();

    expect(snapshot.iosProductionSigningConfigReady, isTrue);
    expect(snapshot.input.iosProductionSigningReady, isTrue);

    expect(
      snapshot.readiness.blockers,
      isNot(contains(ReleaseReadinessBlocker.iosProductionSigningMissing)),
    );
  });

  test('scanner does not consume Apple signing secret material', () {
    final scannerSource = File(
      'lib/core/config/release_readiness_repository.dart',
    ).readAsStringSync();

    for (final forbidden in <String>[
      '.p12',
      '.pfx',
      '.mobileprovision',
      'AuthKey_',
      'security find-identity',
      'Library/MobileDevice/Provisioning Profiles',
      'FASTLANE_PASSWORD',
      'APPLE_ID_PASSWORD',
    ]) {
      expect(
        scannerSource,
        isNot(contains(forbidden)),
        reason: 'scanner must not consume $forbidden',
      );
    }
  });

  test('release contract keeps real Apple signing evidence external', () {
    final contract = File('RELEASE_READINESS.md').readAsStringSync();

    expect(contract, contains('IOS_PRODUCTION_SIGNING_CONFIG_READY'));
    expect(contract, contains('IOS_PRODUCTION_SIGNING_READY'));
    expect(contract, contains('MERZOX_RELEASE_IOS_SIGNING_READY'));
    expect(contract, contains('CODE_SIGN_STYLE = Automatic'));
    expect(contract, contains('macOS/Xcode'));
    expect(contract, matches(RegExp(r'signed\s+archive/export validation')));
    expect(contract, contains('does not invent a `DEVELOPMENT_TEAM`'));
  });
}
