enum NotificationBadgeStatus { initial, loading, ready, failure }

final class NotificationBadgeState {
  final NotificationBadgeStatus status;
  final int unreadCount;
  final String errorMessage;

  const NotificationBadgeState({
    this.status = NotificationBadgeStatus.initial,
    this.unreadCount = 0,
    this.errorMessage = '',
  });

  bool get hasUnread => unreadCount > 0;

  NotificationBadgeState copyWith({
    NotificationBadgeStatus? status,
    int? unreadCount,
    String? errorMessage,
  }) {
    return NotificationBadgeState(
      status: status ?? this.status,
      unreadCount: unreadCount ?? this.unreadCount,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
