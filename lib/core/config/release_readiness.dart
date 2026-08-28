import 'firebase_readiness.dart';

enum ReleaseReadinessBlocker {
  applicationIdentityNotPermanent,
  androidIdentityMismatch,
  iosIdentityMismatch,
  androidReleaseUsesDebugSigning,
  androidProductionSigningMissing,
  iosProductionSigningMissing,
  firebaseProductionActivationMissing,
  playStorePublicationMissing,
  appStorePublicationMissing,
  paymentProductionActivationMissing,
  deploymentActivationMissing,
  telemetryActivationMissing,
  recoveryActivationMissing,
  productionPrivacyLegalApprovalMissing,
  iosPrivacyManifestAuditIncomplete,
}

final class ReleaseReadinessInput {
  final String canonicalApplicationId;
  final String androidApplicationId;
  final String iosBundleIdentifier;
  final bool androidReleaseUsesDebugSigning;
  final bool androidProductionSigningReady;
  final bool iosProductionSigningReady;
  final bool firebaseProductionReady;
  final bool playStorePublicationReady;
  final bool appStorePublicationReady;
  final bool paymentProductionReady;
  final bool deploymentProductionReady;
  final bool telemetryProductionReady;
  final bool recoveryProductionReady;
  final bool productionPrivacyLegalApproved;
  final bool iosPrivacyManifestAuditComplete;

  const ReleaseReadinessInput({
    required this.canonicalApplicationId,
    required this.androidApplicationId,
    required this.iosBundleIdentifier,
    required this.androidReleaseUsesDebugSigning,
    required this.androidProductionSigningReady,
    required this.iosProductionSigningReady,
    required this.firebaseProductionReady,
    required this.playStorePublicationReady,
    required this.appStorePublicationReady,
    required this.paymentProductionReady,
    required this.deploymentProductionReady,
    required this.telemetryProductionReady,
    required this.recoveryProductionReady,
    required this.productionPrivacyLegalApproved,
    required this.iosPrivacyManifestAuditComplete,
  });
}

final class ReleaseReadiness {
  final Set<ReleaseReadinessBlocker> blockers;

  ReleaseReadiness(Iterable<ReleaseReadinessBlocker> blockers)
    : blockers = Set.unmodifiable(blockers);

  bool get canRelease => blockers.isEmpty;
}

ReleaseReadiness evaluateReleaseReadiness(ReleaseReadinessInput input) {
  final blockers = <ReleaseReadinessBlocker>{};

  if (!isPermanentMerzoxApplicationId(input.canonicalApplicationId)) {
    blockers.add(ReleaseReadinessBlocker.applicationIdentityNotPermanent);
  }

  if (input.androidApplicationId != input.canonicalApplicationId) {
    blockers.add(ReleaseReadinessBlocker.androidIdentityMismatch);
  }

  if (input.iosBundleIdentifier != input.canonicalApplicationId) {
    blockers.add(ReleaseReadinessBlocker.iosIdentityMismatch);
  }

  if (input.androidReleaseUsesDebugSigning) {
    blockers.add(ReleaseReadinessBlocker.androidReleaseUsesDebugSigning);
  }

  final readinessFlags = <ReleaseReadinessBlocker, bool>{
    ReleaseReadinessBlocker.androidProductionSigningMissing:
        input.androidProductionSigningReady,
    ReleaseReadinessBlocker.iosProductionSigningMissing:
        input.iosProductionSigningReady,
    ReleaseReadinessBlocker.firebaseProductionActivationMissing:
        input.firebaseProductionReady,
    ReleaseReadinessBlocker.playStorePublicationMissing:
        input.playStorePublicationReady,
    ReleaseReadinessBlocker.appStorePublicationMissing:
        input.appStorePublicationReady,
    ReleaseReadinessBlocker.paymentProductionActivationMissing:
        input.paymentProductionReady,
    ReleaseReadinessBlocker.deploymentActivationMissing:
        input.deploymentProductionReady,
    ReleaseReadinessBlocker.telemetryActivationMissing:
        input.telemetryProductionReady,
    ReleaseReadinessBlocker.recoveryActivationMissing:
        input.recoveryProductionReady,
    ReleaseReadinessBlocker.productionPrivacyLegalApprovalMissing:
        input.productionPrivacyLegalApproved,
    ReleaseReadinessBlocker.iosPrivacyManifestAuditIncomplete:
        input.iosPrivacyManifestAuditComplete,
  };

  for (final entry in readinessFlags.entries) {
    if (!entry.value) {
      blockers.add(entry.key);
    }
  }

  return ReleaseReadiness(blockers);
}
