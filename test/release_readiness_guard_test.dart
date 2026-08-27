import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/config/release_readiness.dart';

ReleaseReadinessInput readyInput({
  String canonicalApplicationId = 'ps.merzoxapp.merzox',
  String androidApplicationId = 'ps.merzoxapp.merzox',
  String iosBundleIdentifier = 'ps.merzoxapp.merzox',
  bool androidReleaseUsesDebugSigning = false,
  bool iosProductionSigningReady = true,
  bool firebaseProductionReady = true,
  bool playStorePublicationReady = true,
  bool appStorePublicationReady = true,
  bool paymentProductionReady = true,
  bool deploymentProductionReady = true,
  bool telemetryProductionReady = true,
  bool recoveryProductionReady = true,
  bool productionPrivacyLegalApproved = true,
  bool iosPrivacyManifestAuditComplete = true,
}) {
  return ReleaseReadinessInput(
    canonicalApplicationId: canonicalApplicationId,
    androidApplicationId: androidApplicationId,
    iosBundleIdentifier: iosBundleIdentifier,
    androidReleaseUsesDebugSigning: androidReleaseUsesDebugSigning,
    iosProductionSigningReady: iosProductionSigningReady,
    firebaseProductionReady: firebaseProductionReady,
    playStorePublicationReady: playStorePublicationReady,
    appStorePublicationReady: appStorePublicationReady,
    paymentProductionReady: paymentProductionReady,
    deploymentProductionReady: deploymentProductionReady,
    telemetryProductionReady: telemetryProductionReady,
    recoveryProductionReady: recoveryProductionReady,
    productionPrivacyLegalApproved: productionPrivacyLegalApproved,
    iosPrivacyManifestAuditComplete: iosPrivacyManifestAuditComplete,
  );
}

void main() {
  test('fully satisfied production contract can release', () {
    final result = evaluateReleaseReadiness(readyInput());

    expect(result.canRelease, isTrue);
    expect(result.blockers, isEmpty);
  });

  test('placeholder canonical identity fails closed', () {
    final result = evaluateReleaseReadiness(
      readyInput(
        canonicalApplicationId: 'com.example.merzox',
        androidApplicationId: 'com.example.merzox',
        iosBundleIdentifier: 'com.example.merzox',
      ),
    );

    expect(result.canRelease, isFalse);
    expect(
      result.blockers,
      contains(ReleaseReadinessBlocker.applicationIdentityNotPermanent),
    );
  });

  test('native application identities must match canonical identity', () {
    final result = evaluateReleaseReadiness(
      readyInput(
        androidApplicationId: 'com.other.merzox',
        iosBundleIdentifier: 'org.other.merzox',
      ),
    );

    expect(
      result.blockers,
      containsAll({
        ReleaseReadinessBlocker.androidIdentityMismatch,
        ReleaseReadinessBlocker.iosIdentityMismatch,
      }),
    );
  });

  test('debug Android release signing blocks production release', () {
    final result = evaluateReleaseReadiness(
      readyInput(androidReleaseUsesDebugSigning: true),
    );

    expect(
      result.blockers,
      contains(ReleaseReadinessBlocker.androidReleaseUsesDebugSigning),
    );
  });

  test('every external production input fails closed when absent', () {
    final result = evaluateReleaseReadiness(
      readyInput(
        iosProductionSigningReady: false,
        firebaseProductionReady: false,
        playStorePublicationReady: false,
        appStorePublicationReady: false,
        paymentProductionReady: false,
        deploymentProductionReady: false,
        telemetryProductionReady: false,
        recoveryProductionReady: false,
        productionPrivacyLegalApproved: false,
        iosPrivacyManifestAuditComplete: false,
      ),
    );

    expect(result.canRelease, isFalse);
    expect(result.blockers.length, 10);
    expect(
      result.blockers,
      containsAll({
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
  });
}
