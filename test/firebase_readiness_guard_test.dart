import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/core/config/firebase_readiness.dart';
import 'package:merzox/services/push_service.dart';

final class _AuthenticatedSessionService extends AuthSessionService {
  const _AuthenticatedSessionService();

  @override
  Future<AuthSessionSnapshot> read() async {
    return const AuthSessionSnapshot(
      type: AuthSessionType.customer,
      token: 'jwt-firebase-guard-test',
    );
  }
}

void main() {
  test('current repository identity is deliberately not production-ready', () {
    expect(merzoxPlatformApplicationId, 'com.example.merzox');

    expect(merzoxFirebasePlatformConfigReady, false);

    expect(currentFirebaseReadiness.canInitialize, false);

    expect(firebasePushRuntimeEnabled, false);
  });

  test('placeholder and temporary identifiers are rejected', () {
    for (final value in [
      '',
      'com.example.merzox',
      'com.merzox.www',
      'com.demo.merzox',
      'com.test.merzox',
      'COM.COMPANY.MERZOX',
    ]) {
      expect(isPermanentMerzoxApplicationId(value), false, reason: value);
    }

    expect(isPermanentMerzoxApplicationId('com.company.merzox'), true);
  });

  test('push request cannot bypass placeholder platform identity', () {
    final readiness = evaluateFirebaseReadiness(
      pushRequested: true,
      applicationId: 'com.example.merzox',
      declaredProductionId: 'com.company.merzox',
      platformConfigReady: true,
    );

    expect(readiness.canInitialize, false);

    expect(
      readiness.blockers,
      contains(FirebaseReadinessBlocker.platformIdentityNotPermanent),
    );
  });

  test('declared production identity must be permanent', () {
    final readiness = evaluateFirebaseReadiness(
      pushRequested: true,
      applicationId: 'com.company.merzox',
      declaredProductionId: 'com.example.merzox',
      platformConfigReady: true,
    );

    expect(readiness.canInitialize, false);

    expect(
      readiness.blockers,
      contains(FirebaseReadinessBlocker.declaredIdentityNotPermanent),
    );
  });

  test('declared identity must exactly match migrated platform identity', () {
    final readiness = evaluateFirebaseReadiness(
      pushRequested: true,
      applicationId: 'com.company.merzox',
      declaredProductionId: 'com.other.merzox',
      platformConfigReady: true,
    );

    expect(readiness.canInitialize, false);

    expect(
      readiness.blockers,
      contains(FirebaseReadinessBlocker.declaredIdentityMismatch),
    );
  });

  test(
    'missing platform config blocks otherwise valid production identity',
    () {
      final readiness = evaluateFirebaseReadiness(
        pushRequested: true,
        applicationId: 'com.company.merzox',
        declaredProductionId: 'com.company.merzox',
        platformConfigReady: false,
      );

      expect(readiness.canInitialize, false);

      expect(
        readiness.blockers,
        contains(FirebaseReadinessBlocker.platformConfigMissing),
      );
    },
  );

  test('push must be explicitly requested', () {
    final readiness = evaluateFirebaseReadiness(
      pushRequested: false,
      applicationId: 'com.company.merzox',
      declaredProductionId: 'com.company.merzox',
      platformConfigReady: true,
    );

    expect(readiness.canInitialize, false);

    expect(
      readiness.blockers,
      contains(FirebaseReadinessBlocker.pushNotRequested),
    );
  });

  test(
    'all production conditions are required before Firebase may initialize',
    () {
      final readiness = evaluateFirebaseReadiness(
        pushRequested: true,
        applicationId: 'com.company.merzox',
        declaredProductionId: 'com.company.merzox',
        platformConfigReady: true,
      );

      expect(readiness.blockers, isEmpty);

      expect(readiness.canInitialize, true);
    },
  );

  test('repository platform identity matches deferred guard constant', () {
    final androidGradle = File(
      'android/app/build.gradle.kts',
    ).readAsStringSync();

    final androidActivity = File(
      'android/app/src/main/java/com/example/merzox/MainActivity.java',
    ).readAsStringSync();

    final iosProject = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    final macosConfig = File(
      'macos/Runner/Configs/AppInfo.xcconfig',
    ).readAsStringSync();

    final linuxCmake = File('linux/CMakeLists.txt').readAsStringSync();

    expect(
      androidGradle,
      contains('namespace = "$merzoxPlatformApplicationId"'),
    );

    expect(
      androidGradle,
      contains('applicationId = "$merzoxPlatformApplicationId"'),
    );

    expect(androidActivity, contains('package $merzoxPlatformApplicationId;'));

    expect(
      iosProject,
      contains(
        'PRODUCT_BUNDLE_IDENTIFIER = '
        '$merzoxPlatformApplicationId;',
      ),
    );

    expect(
      macosConfig,
      contains(
        'PRODUCT_BUNDLE_IDENTIFIER = '
        '$merzoxPlatformApplicationId',
      ),
    );

    expect(
      linuxCmake,
      contains(
        'set(APPLICATION_ID '
        '"$merzoxPlatformApplicationId")',
      ),
    );
  });

  test('production Firebase platform files remain absent while deferred', () {
    expect(File('lib/firebase_options.dart').existsSync(), false);

    expect(File('android/app/google-services.json').existsSync(), false);

    expect(File('ios/Runner/GoogleService-Info.plist').existsSync(), false);
  });

  test(
    'product code does not explicitly bypass PushService readiness guard',
    () {
      final injector = File('lib/injection/injector.dart').readAsStringSync();

      expect(
        injector,
        contains('registerLazySingleton<PushService>(() => PushService())'),
      );

      final dartFiles = Directory('lib')
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));

      for (final file in dartFiles) {
        final normalized = file.path.replaceAll('\\', '/');

        if (normalized.endsWith('/services/push_service.dart')) {
          continue;
        }

        final source = file.readAsStringSync();

        expect(
          RegExp(
            r'PushService\s*\([^)]*\benabled\s*:',
            dotAll: true,
          ).hasMatch(source),
          false,
          reason: file.path,
        );
      }
    },
  );

  test(
    'default PushService cannot construct Firebase client while deferred',
    () async {
      var clientFactoryCalls = 0;

      final service = PushService(
        authSessionService: const _AuthenticatedSessionService(),
        platformResolver: () => PushClientPlatform.android,
        clientFactory: () async {
          clientFactoryCalls += 1;

          throw StateError(
            'Firebase client must not be constructed while deferred',
          );
        },
      );

      await service.syncWithSession();
      await service.startTapHandling();

      expect(service.isEnabled, false);

      expect(clientFactoryCalls, 0);

      await service.close();
    },
  );
}
