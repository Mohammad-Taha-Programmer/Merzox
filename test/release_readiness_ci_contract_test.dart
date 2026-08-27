import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normal CI audits without enforcing production readiness', () {
    final workflow = File('.github/workflows/ci.yml').readAsStringSync();

    expect(workflow, contains('Audit production release readiness'));
    expect(workflow, contains('dart run tool/release_readiness.dart --audit'));
    expect(workflow, isNot(contains('--require-ready')));
  });

  test('CI formatting covers release-readiness tooling', () {
    final workflow = File('.github/workflows/ci.yml').readAsStringSync();

    expect(
      workflow,
      contains('dart format --output=none --set-exit-if-changed lib test tool'),
    );
  });

  test('release contract documents modes and evidence flags', () {
    final contract = File('RELEASE_READINESS.md').readAsStringSync();

    expect(contract, contains('--audit'));
    expect(contract, contains('--require-ready'));
    expect(contract, contains('CAN_RELEASE=false'));
    expect(contract, contains('exits `2`'));
    expect(contract, contains('MERZOX_RELEASE_IOS_SIGNING_READY'));
    expect(contract, contains('MERZOX_RELEASE_IOS_PRIVACY_AUDIT_COMPLETE'));
    expect(contract, contains('Normal CI must not run `--require-ready`'));
  });

  test('README links the authoritative release contract', () {
    final readme = File('README.md').readAsStringSync();

    expect(readme, contains('[RELEASE_READINESS.md](RELEASE_READINESS.md)'));
    expect(readme, contains('dart run tool/release_readiness.dart --audit'));
    expect(
      readme,
      contains('dart run tool/release_readiness.dart --require-ready'),
    );
  });
}
