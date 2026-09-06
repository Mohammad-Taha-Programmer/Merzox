import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/notifications/notifications_visibility.dart';
import 'package:merzox/services/api_service.dart';

/// How much of the list the notifications screen shows.
///
/// The newest fifty, read or unread - except that an unread one has to be
/// younger than a week to count. A notification nobody opened in a week has
/// been answered by events or was never worth answering; a read one has
/// already been dealt with, so its age says nothing about it.
///
/// Nothing here deletes: the record stays on the server, and `مشاهدة المزيد`
/// brings back everything this holds down.

final DateTime _now = DateTime(2026, 9, 6, 12);

AppNotificationApiModel _at({
  required Duration age,
  bool read = false,
  String id = 'n',
}) => AppNotificationApiModel(
  id: id,
  type: 'orderPlaced',
  title: 'طلب جديد',
  body: 'رقم 222321',
  data: const <String, dynamic>{'orderId': 'o1'},
  isRead: read,
  createdAt: _now.subtract(age),
);

List<AppNotificationApiModel> _many(int count, {bool read = false}) =>
    <AppNotificationApiModel>[
      for (int index = 0; index < count; index++)
        _at(
          age: Duration(minutes: index),
          read: read,
          id: 'n$index',
        ),
    ];

void main() {
  group('the default view', () {
    test('it shows the newest fifty and no more', () {
      final List<AppNotificationApiModel> shown = visibleNotifications(
        _many(120),
        now: _now,
      );

      expect(shown, hasLength(kNotificationsPageSize));
      expect(shown.first.id, 'n0', reason: 'the newest must survive');
      expect(shown.last.id, 'n49');
    });

    test('a shorter list is shown whole', () {
      expect(visibleNotifications(_many(3), now: _now), hasLength(3));
      expect(
        visibleNotifications(const <AppNotificationApiModel>[], now: _now),
        isEmpty,
      );
    });

    test('read and unread both count toward the fifty', () {
      final List<AppNotificationApiModel> mixed = <AppNotificationApiModel>[
        ..._many(30, read: true),
        ..._many(30),
      ];

      expect(
        visibleNotifications(mixed, now: _now),
        hasLength(kNotificationsPageSize),
      );
    });
  });

  group('an unread notification that has gone stale', () {
    test('it drops off once it is a week old', () {
      const Duration week = kUnreadNotificationLife;

      expect(
        notificationStillCurrent(
          _at(age: week - const Duration(hours: 1)),
          _now,
        ),
        isTrue,
      );
      expect(notificationStillCurrent(_at(age: week), _now), isFalse);
      expect(
        notificationStillCurrent(
          _at(age: week + const Duration(days: 30)),
          _now,
        ),
        isFalse,
      );
    });

    test('it is hidden from the list, not removed from the record', () {
      final List<AppNotificationApiModel> all = <AppNotificationApiModel>[
        _at(age: const Duration(hours: 1), id: 'fresh'),
        _at(age: const Duration(days: 30), id: 'stale'),
      ];

      expect(
        visibleNotifications(
          all,
          now: _now,
        ).map((AppNotificationApiModel n) => n.id),
        <String>['fresh'],
      );

      // The whole list is still there; only the screen is narrower.
      expect(all, hasLength(2));
      expect(
        visibleNotifications(all, now: _now, showingAll: true),
        hasLength(2),
      );
    });
  });

  group('an old notification that was read', () {
    test('it stays, however old it is', () {
      // It has already been dealt with, so its age says nothing about whether
      // the reader still wants to see it in their history.
      expect(
        notificationStillCurrent(
          _at(age: const Duration(days: 400), read: true),
          _now,
        ),
        isTrue,
      );
    });
  });

  test('one with no timestamp is kept rather than guessed about', () {
    const AppNotificationApiModel undated = AppNotificationApiModel(
      id: 'u',
      type: 'orderPlaced',
      title: 't',
      body: 'b',
      data: <String, dynamic>{},
      isRead: false,
      createdAt: null,
    );

    // A missing date is not evidence of age, and dropping it would lose a
    // notification nobody has read.
    expect(notificationStillCurrent(undated, _now), isTrue);
  });

  group('whether more is being held back', () {
    test('it is, when the rule hid something', () {
      expect(
        notificationsAreHeldBack(_many(51), now: _now, showingAll: false),
        isTrue,
      );
      expect(
        notificationsAreHeldBack(
          <AppNotificationApiModel>[_at(age: const Duration(days: 30))],
          now: _now,
          showingAll: false,
        ),
        isTrue,
      );
    });

    test('it is not, when everything already fits', () {
      expect(
        notificationsAreHeldBack(_many(10), now: _now, showingAll: false),
        isFalse,
      );
    });

    test('once everything is shown, only the server can be holding more', () {
      expect(
        notificationsAreHeldBack(_many(120), now: _now, showingAll: true),
        isFalse,
      );
      expect(
        notificationsAreHeldBack(
          _many(120),
          now: _now,
          showingAll: true,
          serverHasMore: true,
        ),
        isTrue,
      );
    });
  });
}
