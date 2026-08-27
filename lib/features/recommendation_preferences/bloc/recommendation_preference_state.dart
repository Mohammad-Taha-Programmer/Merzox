enum RecommendationPreferenceStatus { initial, loading, ready, saving, failure }

final class RecommendationPreferenceState {
  final RecommendationPreferenceStatus status;
  final bool? enabled;
  final String consentStatus;
  final String errorMessage;

  const RecommendationPreferenceState({
    this.status = RecommendationPreferenceStatus.initial,
    this.enabled,
    this.consentStatus = 'notAsked',
    this.errorMessage = '',
  });
}
