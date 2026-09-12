import 'package:merzox/services/api_service.dart';

/// What one audience's notification feed looked like when the reader last left
/// it.
class NotificationsSessionSnapshot {
  final List<AppNotificationApiModel> notifications;
  final int unreadCount;

  /// The deepest server page fetched so far, so the next `load more` asks for
  /// the page after it rather than starting again.
  final int page;

  final bool hasMore;

  const NotificationsSessionSnapshot({
    required this.notifications,
    required this.unreadCount,
    required this.page,
    required this.hasMore,
  });
}

/// The notification feed, kept for as long as the app is open and no longer.
///
/// Every press of the bell built a new bloc and fetched page one again, so a
/// reader who opened the list three times paid for it three times and watched
/// a spinner each time - on a screen whose contents had not changed between
/// the second press and the third.
///
/// This holds what was already fetched so the second press paints immediately.
/// It is memory and not a file on purpose: the rule is that nothing about
/// notifications survives the app closing, and a process that is gone has
/// already forgotten. Written to disk it would need a cleanup that a crash or
/// a force-stop could skip, and the thing left behind would be one account's
/// notifications sitting on a shared device.
///
/// Two audiences are kept apart. A shop owner reads their own inbox and their
/// shop's, and they are different lists with different unread counts.
///
/// It is cleared on sign-out as well, which the "until the app closes" rule
/// does not cover: the next person to sign in on the same phone must not find
/// the last one's notifications waiting.
class NotificationsSessionStore {
  final Map<String, NotificationsSessionSnapshot> _byAudience =
      <String, NotificationsSessionSnapshot>{};

  static String _key(bool businessAudience) =>
      businessAudience ? 'business' : 'customer';

  /// What is held for this audience, or null if the bell has not been opened
  /// yet in this run of the app.
  NotificationsSessionSnapshot? read(bool businessAudience) =>
      _byAudience[_key(businessAudience)];

  void write(bool businessAudience, NotificationsSessionSnapshot snapshot) {
    _byAudience[_key(businessAudience)] = snapshot;
  }

  /// Forgets everything, for sign-out.
  void clear() => _byAudience.clear();

  /// Whether anything is held at all. For tests and for saying so plainly.
  bool get isEmpty => _byAudience.isEmpty;
}

/// Page one on top of what is already held.
///
/// A notification arriving does not invalidate the pages a reader has scrolled
/// through: replacing the list with page one threw away everything below it
/// and sent them back to the top. The fresh page leads, because the server is
/// the authority on what is newest and on what has been read, and whatever was
/// already held and is not in it keeps its place underneath.
List<AppNotificationApiModel> mergeNotificationPageOne({
  required List<AppNotificationApiModel> held,
  required List<AppNotificationApiModel> fresh,
}) {
  final Set<String> freshIds = <String>{
    for (final AppNotificationApiModel item in fresh) item.id,
  };

  return <AppNotificationApiModel>[
    ...fresh,
    for (final AppNotificationApiModel item in held)
      if (!freshIds.contains(item.id)) item,
  ];
}
