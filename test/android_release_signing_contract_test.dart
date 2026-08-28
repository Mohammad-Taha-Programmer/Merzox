import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'tracked Android release signing is fail closed and has no debug fallback',
    () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();

      expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));

      expect(
        gradle,
        contains('signingConfig = signingConfigs.getByName("release")'),
      );

      for (final marker in <String>[
        'rootProject.file("key.properties")',
        'releaseTaskRequested',
        'requiredReleaseSigningProperties',
        '"storeFile"',
        '"storePassword"',
        '"keyAlias"',
        '"keyPassword"',
        'Merzox release signing requires android/key.properties.',
        'Merzox release signing is missing required properties:',
        'Merzox release signing keystore file does not exist.',
      ]) {
        expect(
          gradle,
          contains(marker),
          reason: 'Missing Android signing contract marker: $marker',
        );
      }
    },
  );

  test('signing material patterns remain ignored by Git', () {
    final ignore = File('android/.gitignore').readAsStringSync();

    expect(ignore, contains('key.properties'));
    expect(ignore, contains('.jks'));
    expect(ignore, contains('.keystore'));
  });

  test(
    'release contract separates repository structure from activation evidence',
    () {
      final contract = File('RELEASE_READINESS.md').readAsStringSync();

      expect(contract, contains('MERZOX_RELEASE_ANDROID_SIGNING_READY'));

      expect(contract, contains('android/key.properties'));

      expect(contract, contains(':app:validateSigningRelease'));

      expect(
        contract,
        matches(RegExp(r'There is no debug-signing\s+fallback\.')),
      );
    },
  );

  test('release scanner does not consume Android signing secret files', () {
    final scanner = File(
      'lib/core/config/release_readiness_repository.dart',
    ).readAsStringSync();

    expect(scanner, contains('MERZOX_RELEASE_ANDROID_SIGNING_READY'));

    expect(scanner, isNot(contains("_readRequired('android/key.properties')")));

    expect(scanner, isNot(contains('readAsBytes')));

    expect(scanner, isNot(contains('MERZOX_RELEASE_ANDROID_STORE_PASSWORD')));

    expect(scanner, isNot(contains('MERZOX_RELEASE_ANDROID_KEY_PASSWORD')));
  });
}
