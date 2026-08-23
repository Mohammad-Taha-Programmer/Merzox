enum NotificationPreferenceStatus { initial, loading, ready, saving, failure }

final class NotificationPreferenceState {
  final NotificationPreferenceStatus status;
  final bool? productOffers;
  final String errorMessage;

  const NotificationPreferenceState({
    this.status = NotificationPreferenceStatus.initial,
    this.productOffers,
    this.errorMessage = '',
  });
}
