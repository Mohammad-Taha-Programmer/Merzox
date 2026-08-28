import 'dart:io';

import 'release_readiness.dart';

final class ReleaseReadinessRepositorySnapshot {
  final ReleaseReadinessInput input;
  final bool firebasePlatformConfigReady;
  final bool androidProductionSigningConfigReady;
  final bool iosProductionSigningConfigReady;

  const ReleaseReadinessRepositorySnapshot({
    required this.input,
    required this.firebasePlatformConfigReady,
    required this.androidProductionSigningConfigReady,
    required this.iosProductionSigningConfigReady,
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

    final androidProductionSigningConfigReady =
        !androidReleaseUsesDebugSigning &&
        _androidProductionSigningConfigReady(androidSource);

    final iosBundleIdentifier = _iosApplicationBundleIdentifier(iosSource);

    final iosProductionSigningConfigReady = _iosProductionSigningConfigReady(
      iosSource,
    );

    final input = ReleaseReadinessInput(
      canonicalApplicationId: canonicalApplicationId,
      androidApplicationId: androidApplicationId,
      iosBundleIdentifier: iosBundleIdentifier,
      androidReleaseUsesDebugSigning: androidReleaseUsesDebugSigning,
      androidProductionSigningReady:
          androidProductionSigningConfigReady &&
          _attested('MERZOX_RELEASE_ANDROID_SIGNING_READY'),
      iosProductionSigningReady:
          iosProductionSigningConfigReady &&
          _attested('MERZOX_RELEASE_IOS_SIGNING_READY'),
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
      androidProductionSigningConfigReady: androidProductionSigningConfigReady,
      iosProductionSigningConfigReady: iosProductionSigningConfigReady,
    );
  }

  bool _androidProductionSigningConfigReady(String source) {
    const requiredMarkers = <String>[
      'rootProject.file("key.properties")',
      'releaseTaskRequested',
      'requiredReleaseSigningProperties',
      '"storeFile"',
      '"storePassword"',
      '"keyAlias"',
      '"keyPassword"',
      'create("release")',
      'signingConfig = signingConfigs.getByName("release")',
      'Merzox release signing requires android/key.properties.',
      'Merzox release signing is missing required properties:',
      'Merzox release signing keystore file does not exist.',
    ];

    return requiredMarkers.every(source.contains);
  }

  bool _iosProductionSigningConfigReady(String source) {
    final runnerRelease = _iosBuildConfiguration(
      source,
      configurationListDescription:
          'Build configuration list for PBXNativeTarget "Runner"',
      configurationName: 'Release',
    );

    final runnerProfile = _iosBuildConfiguration(
      source,
      configurationListDescription:
          'Build configuration list for PBXNativeTarget "Runner"',
      configurationName: 'Profile',
    );

    final projectRelease = _iosBuildConfiguration(
      source,
      configurationListDescription:
          'Build configuration list for PBXProject "Runner"',
      configurationName: 'Release',
    );

    final projectProfile = _iosBuildConfiguration(
      source,
      configurationListDescription:
          'Build configuration list for PBXProject "Runner"',
      configurationName: 'Profile',
    );

    return _iosAutomaticRunnerConfigurationReady(runnerRelease) &&
        _iosAutomaticRunnerConfigurationReady(runnerProfile) &&
        !_iosPinsLegacyDeveloperIdentity(projectRelease) &&
        !_iosPinsLegacyDeveloperIdentity(projectProfile);
  }

  bool _iosAutomaticRunnerConfigurationReady(String source) {
    final automaticSigning = RegExp(
      r'CODE_SIGN_STYLE\s*=\s*Automatic;',
    ).hasMatch(source);

    final manualSigning = RegExp(
      r'CODE_SIGN_STYLE\s*=\s*Manual;',
    ).hasMatch(source);

    final pinnedIdentity = RegExp(
      r'CODE_SIGN_IDENTITY(?:\[[^\]]+\])?\s*=',
    ).hasMatch(source);

    final pinnedProvisioningProfile = RegExp(
      r'PROVISIONING_PROFILE(?:_SPECIFIER)?\s*=',
    ).hasMatch(source);

    return automaticSigning &&
        !manualSigning &&
        source.contains('Release.xcconfig') &&
        !pinnedIdentity &&
        !pinnedProvisioningProfile;
  }

  bool _iosPinsLegacyDeveloperIdentity(String source) {
    return RegExp(
      r'"CODE_SIGN_IDENTITY\[sdk=iphoneos\*\]"\s*=\s*"iPhone Developer";',
    ).hasMatch(source);
  }

  String _iosBuildConfiguration(
    String source, {
    required String configurationListDescription,
    required String configurationName,
  }) {
    final configurationList = _captureRequired(
      source,
      RegExp(
        '/\\* ${RegExp.escape(configurationListDescription)} \\*/'
        r'\s*=\s*\{[\s\S]*?buildConfigurations\s*=\s*\(([\s\S]*?)\);',
      ),
      '$configurationListDescription entries',
    );

    final configurationId = _captureRequired(
      configurationList,
      RegExp(
        '([A-F0-9]+) /\\* '
        '${RegExp.escape(configurationName)}'
        r' \*/',
      ),
      '$configurationListDescription $configurationName id',
    );

    return _captureRequired(
      source,
      RegExp(
        '${RegExp.escape(configurationId)} /\\* '
        '${RegExp.escape(configurationName)}'
        r' \*/\s*=\s*\{([\s\S]*?)'
        r'\r?\n\s*name\s*=\s*'
        '${RegExp.escape(configurationName)}'
        r';\r?\n\s*\};',
        multiLine: true,
      ),
      '$configurationListDescription $configurationName block',
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
