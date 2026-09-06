import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/features/notifications/bloc/notifications_bloc.dart';
import 'package:merzox/features/notifications/bloc/notifications_state.dart';
import 'package:merzox/features/notifications/notifications_visibility.dart';
import 'package:merzox/features/notifications/pages/notifications_page.dart';
import 'package:merzox/services/api_service.dart';

import 'localization_test_harness.dart';

/// What the notifications screen shows, and how.
///
/// The list was unbounded, each row a fixed 48 tall with its text cut off at
/// `...` in twelve point - a notification a reader had to open to find out
/// what it said. And a stale unread one stayed at the top of the pile for
/// ever.

/// A bloc frozen on a list, so the screen fetches nothing.
class _Listed extends NotificationsBloc {
  final NotificationsState _state;

  _Listed(this._state) : super(businessAudience: false);

  @override
  NotificationsState get state => _state;
}

AppNotificationApiModel _item({
  required String id,
  Duration age = const Duration(minutes: 1),
  bool read = false,
  String body = 'رقم 222321',
}) => AppNotificationApiModel(
  id: id,
  type: 'orderPlaced',
  title: 'طلب جديد',
  body: body,
  data: const <String, dynamic>{'orderId': 'o1'},
  isRead: read,
  createdAt: DateTime.now().subtract(age),
);

Future<void> _pumpScreen(
  WidgetTester tester,
  List<AppNotificationApiModel> notifications, {
  bool hasMore = false,
}) {
  return pumpLocalized(
    tester,
    BlocProvider<NotificationsBloc>.value(
      value: _Listed(
        NotificationsState(
          status: NotificationsStatus.ready,
          notifications: notifications,
          hasMore: hasMore,
        ),
      ),
      child: const NotificationsPage(),
    ),
  );
}

const Key _showMore = ValueKey<String>('notifications.showMore');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  group('how much it shows', () {
    testWidgets('a short list is shown whole, with nothing to open', (
      WidgetTester tester,
    ) async {
      await _pumpScreen(tester, <AppNotificationApiModel>[
        for (int index = 0; index < 4; index++) _item(id: 'n$index'),
      ]);

      expect(find.byType(NotificationTile), findsNWidgets(4));
      expect(find.byKey(_showMore), findsNothing);
    });

    testWidgets('a stale unread one is held back, and can be brought out', (
      WidgetTester tester,
    ) async {
      await _pumpScreen(tester, <AppNotificationApiModel>[
        _item(id: 'fresh'),
        _item(id: 'stale', age: const Duration(days: 30)),
      ]);

      expect(find.byType(NotificationTile), findsOneWidget);

      // Held back, not deleted: the record is on the server and this brings
      // it back into view.
      await tester.tap(find.byKey(_showMore));
      await settleFrames(tester);

      expect(find.byType(NotificationTile), findsNWidgets(2));
      expect(find.byKey(_showMore), findsNothing);
    });

    testWidgets('the button offers the server the next page once emptied', (
      WidgetTester tester,
    ) async {
      await _pumpScreen(tester, <AppNotificationApiModel>[
        _item(id: 'only'),
      ], hasMore: true);

      // Nothing of this screen's own is being held back, but the server has
      // more, so the way to it stays offered.
      expect(find.byKey(_showMore), findsOneWidget);
    });
  });

  group('how a notification reads', () {
    testWidgets('it is a box with a margin, filled and bordered alike', (
      WidgetTester tester,
    ) async {
      await _pumpScreen(tester, <AppNotificationApiModel>[_item(id: 'n')]);

      final Container box = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(NotificationTile),
              matching: find.byType(Container),
            )
            .first,
      );

      expect(box.margin, const EdgeInsets.all(5));

      final BoxDecoration decoration = box.decoration! as BoxDecoration;
      final Color fill = decoration.color!;
      expect(fill.a, closeTo(0.7, 0.01));

      // The border is the fill's own colour: the box reads as one soft shape,
      // not as an outlined card.
      expect(decoration.border!.top.color, fill);
    });

    testWidgets('a long one wraps instead of being cut off', (
      WidgetTester tester,
    ) async {
      await _pumpScreen(tester, <AppNotificationApiModel>[
        _item(
          id: 'long',
          body:
              'نصّ طويل جداً لا ينتهي أبداً ويستمر في الامتداد بلا رحمة '
              'حتى يتجاوز السطر الواحد وينزل إلى الذي بعده',
        ),
      ]);

      final Text text = tester.widget<Text>(
        find
            .descendant(
              of: find.byType(NotificationTile),
              matching: find.byType(Text),
            )
            .first,
      );

      // A notification cut off at `...` is one a reader has to open to
      // understand, which defeats a list.
      expect(text.maxLines, isNull);
      expect(text.overflow, isNot(TextOverflow.ellipsis));
    });

    testWidgets('its text is large enough to read', (
      WidgetTester tester,
    ) async {
      await _pumpScreen(tester, <AppNotificationApiModel>[_item(id: 'n')]);

      final Text text = tester.widget<Text>(
        find
            .descendant(
              of: find.byType(NotificationTile),
              matching: find.byType(Text),
            )
            .first,
      );

      expect(text.style?.fontSize, greaterThanOrEqualTo(15));
    });

    testWidgets('an unread one is still told apart from a read one', (
      WidgetTester tester,
    ) async {
      await _pumpScreen(tester, <AppNotificationApiModel>[
        _item(id: 'unread'),
        _item(id: 'read', read: true),
      ]);

      final List<Text> texts = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(NotificationTile),
              matching: find.byType(Text),
            ),
          )
          .toList();

      // The box no longer changes colour with the state, so the weight is the
      // only thing left carrying it.
      expect(texts.first.style?.fontWeight, FontWeight.w700);
      expect(texts[2].style?.fontWeight, FontWeight.w400);
    });
  });

  testWidgets('the screen names itself in bold', (WidgetTester tester) async {
    await _pumpScreen(tester, <AppNotificationApiModel>[_item(id: 'n')]);

    final Text title = tester.widget<Text>(
      find.text('notifications.title'.tr()),
    );

    expect(title.style?.fontWeight, FontWeight.w800);
    expect(title.style?.color, MerzoxColors.kColor2B2B2B);
  });

  test('the screen limit is the one the rule states', () {
    expect(kNotificationsPageSize, 50);
    expect(kUnreadNotificationLife, const Duration(days: 7));
  });
}
