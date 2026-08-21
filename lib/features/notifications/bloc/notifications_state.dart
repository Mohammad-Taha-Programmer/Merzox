import '../../../services/api_service.dart';

enum NotificationsStatus { initial, loading, ready, loadingMore, failure }

final class NotificationsState {
  final NotificationsStatus status;
  final List<AppNotificationApiModel> notifications;
  final int unreadCount;
  final int page;
  final bool hasMore;
  final String errorMessage;

  const NotificationsState({
    this.status = NotificationsStatus.initial,
    this.notifications = const [],
    this.unreadCount = 0,
    this.page = 1,
    this.hasMore = false,
    this.errorMessage = '',
  });

  NotificationsState copyWith({
    NotificationsStatus? status,
    List<AppNotificationApiModel>? notifications,
    int? unreadCount,
    int? page,
    bool? hasMore,
    String? errorMessage,
  }) {
    return NotificationsState(
      status: status ?? this.status,
      notifications: notifications ?? this.notifications,
      unreadCount: unreadCount ?? this.unreadCount,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
