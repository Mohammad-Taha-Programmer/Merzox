import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/config/release_readiness.dart';
import 'package:merzox/core/config/release_readiness_repository.dart';

void writeFixture(
  Directory root, {
  String canonicalId = 'ps.merzoxapp.merzox',
  String androidId = 'ps.merzoxapp.merzox',
  String iosId = 'ps.merzoxapp.merzox',
  bool androidDebugSigning = false,
  bool firebasePlatformReady = true,
}) {
  void write(String relativePath, String content) {
    final file = File(
      <String>[
        root.path,
        ...relativePath.split('/'),
      ].join(Platform.pathSeparator),
    );

    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  write('lib/core/config/firebase_readiness.dart', '''
const String merzoxPlatformApplicationId = '$canonicalId';
const bool merzoxFirebasePlatformConfigReady = $firebasePlatformReady;
''');

  write('android/app/build.gradle.kts', '''
android {
  defaultConfig {
    applicationId = "$androidId"
  }

  buildTypes {
    release {
      ${androidDebugSigning ? 'signingConfig = signingConfigs.getByName("debug")' : 'isMinifyEnabled = true'}
    }
  }
}
''');

  write('ios/Runner.xcodeproj/project.pbxproj', '''
PRODUCT_BUNDLE_IDENTIFIER = $iosId;
PRODUCT_BUNDLE_IDENTIFIER = $iosId.RunnerTests;
''');
}

Map<String, String> allAttestations() {
  return const {
    'MERZOX_RELEASE_IOS_SIGNING_READY': 'true',
    'MERZOX_RELEASE_FIREBASE_READY': 'true',
    'MERZOX_RELEASE_PLAY_STORE_READY': 'true',
    'MERZOX_RELEASE_APP_STORE_READY': 'true',
    'MERZOX_RELEASE_PAYMENT_READY': 'true',
    'MERZOX_RELEASE_DEPLOYMENT_READY': 'true',
    'MERZOX_RELEASE_TELEMETRY_READY': 'true',
    'MERZOX_RELEASE_RECOVERY_READY': 'true',
    'MERZOX_RELEASE_PRIVACY_LEGAL_APPROVED': 'true',
    'MERZOX_RELEASE_IOS_PRIVACY_AUDIT_COMPLETE': 'true',
  };
}

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('merzox-release-readiness-');
  });

  tearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  test('repository facts plus all attestations can satisfy contract', () {
    writeFixture(root);

    final snapshot = ReleaseReadinessRepositoryScanner(
      root: root,
      environment: allAttestations(),
    ).scan();

    expect(snapshot.firebasePlatformConfigReady, isTrue);
    expect(snapshot.readiness.canRelease, isTrue);
    expect(snapshot.readiness.blockers, isEmpty);
  });

  test('placeholder identity and debug signing fail closed', () {
    writeFixture(
      root,
      canonicalId: 'com.example.merzox',
      androidId: 'com.example.merzox',
      iosId: 'com.example.merzox',
      androidDebugSigning: true,
      firebasePlatformReady: false,
    );

    final snapshot = ReleaseReadinessRepositoryScanner(
      root: root,
      environment: const {},
    ).scan();

    expect(snapshot.readiness.canRelease, isFalse);

    expect(
      snapshot.readiness.blockers,
      containsAll({
        ReleaseReadinessBlocker.applicationIdentityNotPermanent,
        ReleaseReadinessBlocker.androidReleaseUsesDebugSigning,
        ReleaseReadinessBlocker.iosProductionSigningMissing,
        ReleaseReadinessBlocker.firebaseProductionActivationMissing,
        ReleaseReadinessBlocker.playStorePublicationMissing,
        ReleaseReadinessBlocker.appStorePublicationMissing,
        ReleaseReadinessBlocker.paymentProductionActivationMissing,
        ReleaseReadinessBlocker.deploymentActivationMissing,
        ReleaseReadinessBlocker.telemetryActivationMissing,
        ReleaseReadinessBlocker.recoveryActivationMissing,
        ReleaseReadinessBlocker.productionPrivacyLegalApprovalMissing,
        ReleaseReadinessBlocker.iosPrivacyManifestAuditIncomplete,
      }),
    );

    expect(snapshot.readiness.blockers.length, 12);
  });

  test('native identity divergence is detected independently', () {
    writeFixture(
      root,
      androidId: 'org.other.merzox',
      iosId: 'net.other.merzox',
    );

    final snapshot = ReleaseReadinessRepositoryScanner(
      root: root,
      environment: allAttestations(),
    ).scan();

    expect(
      snapshot.readiness.blockers,
      containsAll({
        ReleaseReadinessBlocker.androidIdentityMismatch,
        ReleaseReadinessBlocker.iosIdentityMismatch,
      }),
    );
  });

  test('Firebase attestation cannot bypass repository readiness flag', () {
    writeFixture(root, firebasePlatformReady: false);

    final snapshot = ReleaseReadinessRepositoryScanner(
      root: root,
      environment: allAttestations(),
    ).scan();

    expect(snapshot.firebasePlatformConfigReady, isFalse);

    expect(
      snapshot.readiness.blockers,
      contains(ReleaseReadinessBlocker.firebaseProductionActivationMissing),
    );
  });

  test('missing required native source fails the scan', () {
    writeFixture(root);

    File(
      <String>[
        root.path,
        'android',
        'app',
        'build.gradle.kts',
      ].join(Platform.pathSeparator),
    ).deleteSync();

    expect(
      () => ReleaseReadinessRepositoryScanner(
        root: root,
        environment: allAttestations(),
      ).scan(),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('ambiguous iOS application identities fail the scan', () {
    writeFixture(root);

    final project = File(
      <String>[
        root.path,
        'ios',
        'Runner.xcodeproj',
        'project.pbxproj',
      ].join(Platform.pathSeparator),
    );

    project.writeAsStringSync('''
PRODUCT_BUNDLE_IDENTIFIER = ps.first.merzox;
PRODUCT_BUNDLE_IDENTIFIER = ps.second.merzox;
''');

    expect(
      () => ReleaseReadinessRepositoryScanner(
        root: root,
        environment: allAttestations(),
      ).scan(),
      throwsA(isA<FormatException>()),
    );
  });
}
