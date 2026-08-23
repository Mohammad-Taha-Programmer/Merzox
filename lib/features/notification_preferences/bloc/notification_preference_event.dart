sealed class NotificationPreferenceEvent {
  const NotificationPreferenceEvent();
}

final class NotificationPreferenceStarted extends NotificationPreferenceEvent {
  const NotificationPreferenceStarted();
}

final class NotificationPreferenceRetryRequested
    extends NotificationPreferenceEvent {
  const NotificationPreferenceRetryRequested();
}

final class NotificationPreferenceChanged extends NotificationPreferenceEvent {
  final bool productOffers;

  const NotificationPreferenceChanged(this.productOffers);
}
