import 'package:merzox/services/api_service.dart';

/// How much of the list the screen shows before it is asked for more.
const int kNotificationsPageSize = 50;

/// How long an unread notification stays on the screen.
///
/// A notification nobody opened in a week has been answered by events or was
/// never worth answering; either way it is no longer news, and a list that
/// keeps them is a list a merchant stops reading. It is hidden, not deleted -
/// the record stays on the server, and `مشاهدة المزيد` brings it back.
const Duration kUnreadNotificationLife = Duration(days: 7);

/// What the notifications screen shows by default.
///
/// The newest fifty, read or unread - except that an unread one has to be
/// younger than a week to count. A read notification stays eligible however
/// old it is: it has already been dealt with, so its age says nothing.
///
/// [now] is passed rather than read from the clock so a test can state what
/// "a week old" means on a given day.
List<AppNotificationApiModel> visibleNotifications(
  List<AppNotificationApiModel> all, {
  required DateTime now,
  bool showingAll = false,
}) {
  if (showingAll) return all;

  final List<AppNotificationApiModel> fresh = all
      .where(
        (AppNotificationApiModel item) => notificationStillCurrent(item, now),
      )
      .toList();

  return fresh.length <= kNotificationsPageSize
      ? fresh
      : fresh.sublist(0, kNotificationsPageSize);
}

/// Whether one notification still belongs on the default screen.
bool notificationStillCurrent(AppNotificationApiModel item, DateTime now) {
  if (item.isRead) return true;

  final DateTime? raised = item.createdAt;
  // No timestamp is not evidence of age, and dropping it would lose a
  // notification nobody has read.
  if (raised == null) return true;

  return now.difference(raised) < kUnreadNotificationLife;
}

/// Whether anything is being held back, which is the only reason to offer
/// `مشاهدة المزيد`.
bool notificationsAreHeldBack(
  List<AppNotificationApiModel> all, {
  required DateTime now,
  required bool showingAll,
  bool serverHasMore = false,
}) {
  if (showingAll) return serverHasMore;

  return serverHasMore ||
      visibleNotifications(all, now: now).length < all.length;
}
