const consentStatuses = new Set([
  'notAsked',
  'granted',
  'denied'
]);

export function recommendationConsentStatus(user) {
  const status =
    user?.permissionConsents?.aiPersonalization?.status;

  return consentStatuses.has(status)
    ? status
    : 'notAsked';
}

/**
 * Personalization authority is deliberately fail-closed.
 *
 * A legacy/stale boolean is insufficient by itself, and a consent record
 * marked granted is also insufficient if the current permission has been
 * switched off. Both authoritative facts must agree.
 */
export function hasRecommendationConsent(user) {
  return (
    user?.permissions?.aiPersonalization === true &&
    recommendationConsentStatus(user) === 'granted'
  );
}

export function recommendationConsentView(user) {
  return {
    enabled: hasRecommendationConsent(user),
    status: recommendationConsentStatus(user)
  };
}
