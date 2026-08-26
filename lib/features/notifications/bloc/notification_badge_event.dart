sealed class NotificationBadgeEvent {
  const NotificationBadgeEvent();
}

final class NotificationBadgeStarted extends NotificationBadgeEvent {
  const NotificationBadgeStarted();
}

/// Internal authoritative refresh raised by realtime/reconnect.
final class NotificationBadgeRealtimeSyncRequested
    extends NotificationBadgeEvent {
  const NotificationBadgeRealtimeSyncRequested();
}
