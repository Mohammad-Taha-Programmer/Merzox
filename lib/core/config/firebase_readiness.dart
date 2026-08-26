/// Production Firebase activation policy for Merzox.
///
/// The repository intentionally remains on a development placeholder identity
/// until a permanent application namespace is selected. Firebase push therefore
/// fails closed even when MERZOX_FIREBASE_PUSH_ENABLED is accidentally enabled.
const String merzoxPlatformApplicationId = 'com.example.merzox';

/// This becomes true only in the future reviewed change that introduces the
/// final Android/iOS Firebase registrations and platform configuration files.
const bool merzoxFirebasePlatformConfigReady = false;

const bool _firebasePushRequested = bool.fromEnvironment(
  'MERZOX_FIREBASE_PUSH_ENABLED',
  defaultValue: false,
);

const String _declaredFirebaseProductionId = String.fromEnvironment(
  'MERZOX_FIREBASE_PRODUCTION_ID',
  defaultValue: '',
);

enum FirebaseReadinessBlocker {
  pushNotRequested,
  platformIdentityNotPermanent,
  declaredIdentityNotPermanent,
  declaredIdentityMismatch,
  platformConfigMissing,
}

final class FirebaseReadiness {
  final Set<FirebaseReadinessBlocker> blockers;

  FirebaseReadiness(Iterable<FirebaseReadinessBlocker> blockers)
    : blockers = Set<FirebaseReadinessBlocker>.unmodifiable(blockers);

  bool get canInitialize => blockers.isEmpty;
}

bool isPermanentMerzoxApplicationId(String value) {
  if (value.isEmpty || value != value.trim() || value != value.toLowerCase()) {
    return false;
  }

  final segments = value.split('.');

  if (segments.length < 3 || segments.last != 'merzox') {
    return false;
  }

  final segmentPattern = RegExp(r'^[a-z][a-z0-9]*$');

  if (segments.any((segment) => !segmentPattern.hasMatch(segment))) {
    return false;
  }

  const forbiddenSegments = <String>{
    'example',
    'test',
    'testing',
    'local',
    'localhost',
    'sample',
    'demo',
    'placeholder',
    'changeme',
    'organization',
    'yourcompany',
    'yourorganization',
    'www',
  };

  if (segments.any(forbiddenSegments.contains)) {
    return false;
  }

  return true;
}

FirebaseReadiness evaluateFirebaseReadiness({
  required bool pushRequested,
  required String applicationId,
  required String declaredProductionId,
  required bool platformConfigReady,
}) {
  final blockers = <FirebaseReadinessBlocker>{};

  if (!pushRequested) {
    blockers.add(FirebaseReadinessBlocker.pushNotRequested);
  }

  if (!isPermanentMerzoxApplicationId(applicationId)) {
    blockers.add(FirebaseReadinessBlocker.platformIdentityNotPermanent);
  }

  if (!isPermanentMerzoxApplicationId(declaredProductionId)) {
    blockers.add(FirebaseReadinessBlocker.declaredIdentityNotPermanent);
  }

  if (applicationId != declaredProductionId) {
    blockers.add(FirebaseReadinessBlocker.declaredIdentityMismatch);
  }

  if (!platformConfigReady) {
    blockers.add(FirebaseReadinessBlocker.platformConfigMissing);
  }

  return FirebaseReadiness(blockers);
}

FirebaseReadiness get currentFirebaseReadiness => evaluateFirebaseReadiness(
  pushRequested: _firebasePushRequested,
  applicationId: merzoxPlatformApplicationId,
  declaredProductionId: _declaredFirebaseProductionId,
  platformConfigReady: merzoxFirebasePlatformConfigReady,
);

/// The only default production path allowed to enable PushService.
///
/// Tests retain PushService's explicit injected `enabled` seam so Firebase
/// behavior can be validated without platform credentials.
bool get firebasePushRuntimeEnabled => currentFirebaseReadiness.canInitialize;
