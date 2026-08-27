sealed class RecommendationPreferenceEvent {
  const RecommendationPreferenceEvent();
}

final class RecommendationPreferenceStarted
    extends RecommendationPreferenceEvent {
  const RecommendationPreferenceStarted();
}

final class RecommendationPreferenceRetryRequested
    extends RecommendationPreferenceEvent {
  const RecommendationPreferenceRetryRequested();
}

final class RecommendationPreferenceChanged
    extends RecommendationPreferenceEvent {
  final bool enabled;

  const RecommendationPreferenceChanged(this.enabled);
}
