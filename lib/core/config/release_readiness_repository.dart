import 'dart:io';

import 'release_readiness.dart';

final class ReleaseReadinessRepositorySnapshot {
  final ReleaseReadinessInput input;
  final bool firebasePlatformConfigReady;

  const ReleaseReadinessRepositorySnapshot({
    required this.input,
    required this.firebasePlatformConfigReady,
  });

  ReleaseReadiness get readiness => evaluateReleaseReadiness(input);
}

final class ReleaseReadinessRepositoryScanner {
  final Directory root;
  final Map<String, String> environment;

  ReleaseReadinessRepositoryScanner({
    Directory? root,
    Map<String, String>? environment,
  }) : root = root ?? Directory.current,
       environment = environment ?? Platform.environment;

  ReleaseReadinessRepositorySnapshot scan() {
    final firebaseSource = _readRequired(
      'lib/core/config/firebase_readiness.dart',
    );

    final androidSource = _readRequired('android/app/build.gradle.kts');

    final iosSource = _readRequired('ios/Runner.xcodeproj/project.pbxproj');

    final canonicalApplicationId = _captureRequired(
      firebaseSource,
      RegExp(r"const String merzoxPlatformApplicationId\s*=\s*'([^']+)';"),
      'canonical Merzox application identity',
    );

    final firebasePlatformConfigReady =
        _captureRequired(
          firebaseSource,
          RegExp(
            r'const bool merzoxFirebasePlatformConfigReady\s*=\s*(true|false);',
          ),
          'Firebase platform readiness flag',
        ) ==
        'true';

    final androidApplicationId = _captureRequired(
      androidSource,
      RegExp(r'applicationId\s*=\s*"([^"]+)"'),
      'Android applicationId',
    );

    final androidReleaseSection = _captureRequired(
      androidSource,
      RegExp(r'release\s*\{([\s\S]*?)\n\s*\}', multiLine: true),
      'Android release build block',
    );

    final androidReleaseUsesDebugSigning = RegExp(
      r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
    ).hasMatch(androidReleaseSection);

    final iosBundleIdentifier = _iosApplicationBundleIdentifier(iosSource);

    final input = ReleaseReadinessInput(
      canonicalApplicationId: canonicalApplicationId,
      androidApplicationId: androidApplicationId,
      iosBundleIdentifier: iosBundleIdentifier,
      androidReleaseUsesDebugSigning: androidReleaseUsesDebugSigning,
      iosProductionSigningReady: _attested('MERZOX_RELEASE_IOS_SIGNING_READY'),
      firebaseProductionReady:
          firebasePlatformConfigReady &&
          _attested('MERZOX_RELEASE_FIREBASE_READY'),
      playStorePublicationReady: _attested('MERZOX_RELEASE_PLAY_STORE_READY'),
      appStorePublicationReady: _attested('MERZOX_RELEASE_APP_STORE_READY'),
      paymentProductionReady: _attested('MERZOX_RELEASE_PAYMENT_READY'),
      deploymentProductionReady: _attested('MERZOX_RELEASE_DEPLOYMENT_READY'),
      telemetryProductionReady: _attested('MERZOX_RELEASE_TELEMETRY_READY'),
      recoveryProductionReady: _attested('MERZOX_RELEASE_RECOVERY_READY'),
      productionPrivacyLegalApproved: _attested(
        'MERZOX_RELEASE_PRIVACY_LEGAL_APPROVED',
      ),
      iosPrivacyManifestAuditComplete: _attested(
        'MERZOX_RELEASE_IOS_PRIVACY_AUDIT_COMPLETE',
      ),
    );

    return ReleaseReadinessRepositorySnapshot(
      input: input,
      firebasePlatformConfigReady: firebasePlatformConfigReady,
    );
  }

  bool _attested(String name) {
    return environment[name]?.trim().toLowerCase() == 'true';
  }

  String _readRequired(String relativePath) {
    final file = File(_absolutePath(relativePath));

    if (!file.existsSync()) {
      throw FileSystemException(
        'Required release-readiness source is missing.',
        relativePath,
      );
    }

    return file.readAsStringSync();
  }

  String _absolutePath(String relativePath) {
    final segments = relativePath.split('/');

    return <String>[root.path, ...segments].join(Platform.pathSeparator);
  }

  String _captureRequired(String source, RegExp pattern, String description) {
    final match = pattern.firstMatch(source);

    if (match == null || match.groupCount < 1) {
      throw FormatException('Unable to resolve $description.');
    }

    final value = match.group(1)?.trim() ?? '';

    if (value.isEmpty) {
      throw FormatException('Resolved $description is empty.');
    }

    return value;
  }

  String _iosApplicationBundleIdentifier(String source) {
    final identifiers = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);')
        .allMatches(source)
        .map((match) => match.group(1)?.trim() ?? '')
        .map(
          (value) => value.startsWith('"') && value.endsWith('"')
              ? value.substring(1, value.length - 1)
              : value,
        )
        .where((value) => value.isNotEmpty)
        .where((value) => !value.endsWith('.RunnerTests'))
        .toSet();

    if (identifiers.length != 1) {
      throw FormatException(
        'Expected exactly one iOS application bundle identifier.',
      );
    }

    return identifiers.single;
  }
}
