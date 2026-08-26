sealed class NotificationsEvent {
  const NotificationsEvent();
}

final class NotificationsStarted extends NotificationsEvent {
  const NotificationsStarted();
}

final class NotificationsRefreshRequested extends NotificationsEvent {
  const NotificationsRefreshRequested();
}

final class NotificationsLoadMoreRequested extends NotificationsEvent {
  const NotificationsLoadMoreRequested();
}

final class NotificationMarkedRead extends NotificationsEvent {
  final String notificationId;

  const NotificationMarkedRead(this.notificationId);
}

final class NotificationsAllMarkedRead extends NotificationsEvent {
  const NotificationsAllMarkedRead();
}

/// Internal invalidation raised by Socket.IO/reconnect.
///
/// Socket payloads never become notification rows directly. The BLoC re-reads
/// the authoritative REST/MongoDB feed for its customer/business audience.
final class NotificationsRealtimeSyncRequested extends NotificationsEvent {
  const NotificationsRealtimeSyncRequested();
}
