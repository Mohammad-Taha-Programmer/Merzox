import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/features/notifications/bloc/notification_badge_bloc.dart';
import 'package:merzox/features/notifications/bloc/notification_badge_state.dart';
import 'package:merzox/features/notifications/widgets/global_notification_bell.dart';

import 'localization_test_harness.dart';

/// The one bell that floats over every screen.
///
/// Every screen used to draw its own, and several drew none - so a merchant
/// deep in a product editor could take an order and have no way to know it had
/// arrived. And what it drew was a dot: a dot says only that something
/// happened, which is not what a merchant deciding whether to stop what they
/// are doing needs to know.

class _Counted extends NotificationBadgeBloc {
  final int count;

  _Counted(this.count);

  @override
  NotificationBadgeState get state =>
      NotificationBadgeState(unreadCount: count);
}

class _Session implements AuthSessionService {
  final AuthSessionSnapshot snapshot;

  const _Session(this.snapshot);

  @override
  Future<AuthSessionSnapshot> read() async => snapshot;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Pumped with nothing above it.
///
/// Not a `Scaffold`, not a `MaterialApp`, not a router. The bell hangs above
/// the app's router, outside the Navigator that owns the Overlay and outside
/// any `GoRouter` in the tree - so a harness that supplies those is a kinder
/// world than the one it lives in, and three separate crashes reached a phone
/// while the tests were green in it.
Future<void> _pumpBell(
  WidgetTester tester,
  int count, {
  bool businessAudience = true,
  void Function(String location)? onOpen,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.rtl,
      child: MediaQuery(
        data: const MediaQueryData(),
        child: GlobalNotificationBell(
          businessAudience: businessAudience,
          onOpen: onOpen ?? (String _) {},
          blocBuilder: () => _Counted(count),
        ),
      ),
    ),
  );
  await settleFrames(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  group('the count', () {
    testWidgets('it shows how many are waiting, not merely that some are', (
      WidgetTester tester,
    ) async {
      await _pumpBell(tester, 7);

      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('a large count is capped rather than allowed to grow', (
      WidgetTester tester,
    ) async {
      await _pumpBell(tester, 128);

      // Past ninety-nine the exact number is not one anyone acts on, and a
      // four-digit badge would be wider than the bell it sits on.
      expect(find.text('99+'), findsOneWidget);
      expect(find.text('128'), findsNothing);
    });

    testWidgets('the boundary is inclusive', (WidgetTester tester) async {
      await _pumpBell(tester, UnreadCountBadge.max);
      expect(find.text('99'), findsOneWidget);
    });

    testWidgets('nothing unread draws no badge at all', (
      WidgetTester tester,
    ) async {
      await _pumpBell(tester, 0);

      expect(
        find.byKey(const ValueKey<String>('merzox.unreadCount')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('merzox.globalBell')),
        findsOneWidget,
        reason: 'the bell itself stays; only the count comes and goes',
      );
    });
  });

  testWidgets('the bell is the sky blue it was asked to be', (
    WidgetTester tester,
  ) async {
    await _pumpBell(tester, 1);

    final Icon bell = tester.widget<Icon>(
      find.byIcon(Icons.notifications_none_rounded),
    );
    expect(bell.color, MerzoxColors.kColor98C1D9);
  });

  group('which screens it stands over', () {
    test('it follows the reader everywhere they can be reached', () {
      for (final String location in <String>[
        '/home',
        '/business',
        '/business/orders/64d0',
        '/orders',
        '/orders/64d0/tracking',
        '/profile',
        '/chat?conversationId=c1',
        '/cart',
      ]) {
        expect(
          globalBellWantedAt(location),
          isTrue,
          reason: '$location leaves the reader with no way to see an arrival',
        );
      }
    });

    test('it stays off the screen it would only lead back to', () {
      expect(globalBellWantedAt('/notifications'), isFalse);
      expect(globalBellWantedAt('/notifications?audience=business'), isFalse);
    });

    test('and off everything that comes before a session', () {
      // Nothing to count for someone who has not signed in, and a bell over a
      // login form is noise.
      for (final String location in <String>[
        '/login',
        '/signup',
        '/onboarding',
        '/splash',
        '/business/login',
        '/business/enroll',
      ]) {
        expect(globalBellWantedAt(location), isFalse, reason: location);
      }
    });
  });

  group('whose notifications it counts', () {
    testWidgets('a merchant reads their shop own', (WidgetTester tester) async {
      bool? audience;

      await pumpLocalized(
        tester,
        GlobalBellAudience(
          sessionService: const _Session(
            AuthSessionSnapshot(type: AuthSessionType.business, token: 't'),
          ),
          builder: (BuildContext _, bool businessAudience) {
            audience = businessAudience;
            return const SizedBox.shrink();
          },
        ),
      );

      expect(audience, isTrue);
    });

    testWidgets('a customer reads their own', (WidgetTester tester) async {
      bool? audience;

      await pumpLocalized(
        tester,
        GlobalBellAudience(
          sessionService: const _Session(
            AuthSessionSnapshot(type: AuthSessionType.customer, token: 't'),
          ),
          builder: (BuildContext _, bool businessAudience) {
            audience = businessAudience;
            return const SizedBox.shrink();
          },
        ),
      );

      expect(audience, isFalse);
    });

    testWidgets('nobody signed in means no bell, not a guessed audience', (
      WidgetTester tester,
    ) async {
      bool built = false;

      await pumpLocalized(
        tester,
        GlobalBellAudience(
          sessionService: const _Session(
            AuthSessionSnapshot(type: AuthSessionType.unauthenticated),
          ),
          builder: (BuildContext _, bool _) {
            built = true;
            return const SizedBox.shrink();
          },
        ),
      );

      // A bell counting the wrong side's notifications is worse than none.
      expect(built, isFalse);
    });
  });

  group('where it actually hangs', () {
    testWidgets('it builds with no Overlay above it', (
      WidgetTester tester,
    ) async {
      // Anything needing one - a `Tooltip`, most obviously - throws on build
      // there, and the framework paints the error over the whole app.
      await _pumpBell(tester, 4);

      expect(tester.takeException(), isNull);
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('and it can be tapped with no router above it either', (
      WidgetTester tester,
    ) async {
      final List<String> opened = <String>[];
      await _pumpBell(tester, 1, onOpen: opened.add);

      // `context.push` looks a `GoRouter` up through the tree and throws when
      // there is none. There is none here, and there is none in the app.
      await tester.tap(find.byKey(const ValueKey<String>('merzox.globalBell')));
      await settleFrames(tester);

      expect(tester.takeException(), isNull);
      expect(opened, <String>['/notifications?audience=business']);
    });

    testWidgets('a customer is sent to their own list', (
      WidgetTester tester,
    ) async {
      final List<String> opened = <String>[];
      await _pumpBell(tester, 1, businessAudience: false, onOpen: opened.add);

      await tester.tap(find.byKey(const ValueKey<String>('merzox.globalBell')));
      await settleFrames(tester);

      expect(opened, <String>['/notifications']);
    });
  });

  testWidgets('a reader who cannot see it is still told what it is', (
    WidgetTester tester,
  ) async {
    await _pumpBell(tester, 2);

    // `InkWell` wraps its own unnamed `Semantics`, so the one that carries a
    // label is what is being looked for, not the first in the subtree.
    final Iterable<Semantics> named = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .where((Semantics node) => node.properties.label != null);

    // The label is what replaced the tooltip, not a nicety: without it the
    // control is an unnamed shape to anyone who cannot see it.
    expect(
      named.map((Semantics node) => node.properties.label),
      contains('notifications.title'.tr()),
    );
  });

  testWidgets('it stands out from whatever is behind it', (
    WidgetTester tester,
  ) async {
    await _pumpBell(tester, 1);

    // Not a colour chosen per screen. The bell floats over every screen and
    // any of them may be the same blue - the merchant profile's header is
    // exactly this one, and the bell vanished into it. A screen-by-screen fix
    // would leave the next screen to break.
    final Material disc = tester.widget<Material>(
      find
          .ancestor(
            of: find.byKey(const ValueKey<String>('merzox.globalBell')),
            matching: find.byType(Material),
          )
          .first,
    );

    expect(disc.color, Colors.white);
    expect(disc.shape, isA<CircleBorder>());
    expect(
      disc.color,
      isNot(MerzoxColors.kColor98C1D9),
      reason: 'the disc must not be the colour of the bell on it',
    );
  });
}
