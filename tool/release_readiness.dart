import 'dart:io';

import 'package:merzox/core/config/release_readiness_repository.dart';

const _auditMode = '--audit';
const _requireReadyMode = '--require-ready';

void main(List<String> arguments) {
  if (arguments.length != 1 ||
      (arguments.single != _auditMode &&
          arguments.single != _requireReadyMode)) {
    stderr.writeln(
      'Usage: dart run tool/release_readiness.dart '
      '--audit|--require-ready',
    );
    exitCode = 64;
    return;
  }

  final mode = arguments.single;

  try {
    final snapshot = ReleaseReadinessRepositoryScanner().scan();
    final readiness = snapshot.readiness;

    stdout.writeln('MODE=${mode == _auditMode ? 'AUDIT' : 'REQUIRE_READY'}');
    stdout.writeln('CAN_RELEASE=${readiness.canRelease}');
    stdout.writeln(
      'CANONICAL_APPLICATION_ID='
      '${snapshot.input.canonicalApplicationId}',
    );
    stdout.writeln(
      'ANDROID_APPLICATION_ID='
      '${snapshot.input.androidApplicationId}',
    );
    stdout.writeln(
      'IOS_BUNDLE_IDENTIFIER='
      '${snapshot.input.iosBundleIdentifier}',
    );
    stdout.writeln(
      'ANDROID_RELEASE_DEBUG_SIGNING='
      '${snapshot.input.androidReleaseUsesDebugSigning}',
    );
    stdout.writeln(
      'FIREBASE_PLATFORM_CONFIG_READY='
      '${snapshot.firebasePlatformConfigReady}',
    );

    final blockers = readiness.blockers.toList()
      ..sort((left, right) => left.name.compareTo(right.name));

    stdout.writeln('BLOCKER_COUNT=${blockers.length}');

    for (final blocker in blockers) {
      stdout.writeln('BLOCKER=${blocker.name}');
    }

    if (mode == _requireReadyMode && !readiness.canRelease) {
      exitCode = 2;
    }
  } catch (error) {
    stderr.writeln('RELEASE_READINESS_SCAN_ERROR=${error.runtimeType}');
    exitCode = 3;
  }
}
