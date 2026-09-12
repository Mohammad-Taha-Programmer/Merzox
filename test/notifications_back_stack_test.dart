import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:merzox/features/notifications/notifications_excursion.dart';

/// How long the way back is after reading notifications.
///
/// Reported from a phone: open a notification, press the bell, open another,
/// press the bell, open a third - and then it takes six presses of the back
/// button to reach the home screen. The screen a notification opens is pushed
/// over the list it was tapped in, and the bell pushed the list again over
/// that, so the stack grew by two for every notification read and the way out
/// grew with it.
///
/// These tests count screens rather than describe them, because the fault was
/// a number: not that the wrong screen showed, but that too many were still
/// underneath it.

/// The three screens a notification excursion touches, and one that has
/// nothing to do with it.
GoRouter _router() => GoRouter(
  initialLocation: '/home',
  routes: <RouteBase>[
    GoRoute(path: '/home', builder: (_, _) => const Text('home')),
    GoRoute(path: '/cart', builder: (_, _) => const Text('cart')),
    GoRoute(
      path: '/notifications',
      builder: (_, _) => const Text('notifications'),
    ),
    GoRoute(
      path: '/orders/:id/tracking',
      builder: (_, _) => const Text('tracking'),
    ),
  ],
);

int _depth(GoRouter router) =>
    router.routerDelegate.currentConfiguration.matches.length;

void main() {
  late GoRouter router;
  late NotificationsExcursion excursion;

  Future<void> pump(WidgetTester tester) async {
    router = _router();
    addTearDown(router.dispose);

    excursion = NotificationsExcursion(router);
    router.routerDelegate.addListener(excursion.forgetAnchorOnLeaving);
    addTearDown(
      () =>
          router.routerDelegate.removeListener(excursion.forgetAnchorOnLeaving),
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  /// What the reader does: bell, then tap a notification.
  Future<void> readOne(WidgetTester tester, String orderId) async {
    excursion.toggle('/notifications');
    await tester.pumpAndSettle();

    // The notifications page's own tap handler pushes over itself.
    router.push('/orders/$orderId/tracking');
    await tester.pumpAndSettle();
  }

  testWidgets('reading three notifications is no deeper than reading one', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    expect(_depth(router), 1, reason: 'the reader starts on one screen');

    await readOne(tester, '1');
    final int afterFirst = _depth(router);

    await readOne(tester, '2');
    await readOne(tester, '3');

    expect(
      _depth(router),
      afterFirst,
      reason:
          'every notification read used to add two screens that were never '
          'taken away, so the third left six under it',
    );
    expect(find.text('tracking'), findsOneWidget);
  });

  testWidgets('and the way home is the same length either way', (
    WidgetTester tester,
  ) async {
    await pump(tester);

    await readOne(tester, '1');
    await readOne(tester, '2');
    await readOne(tester, '3');

    int presses = 0;
    while (router.canPop() && presses < 10) {
      router.pop();
      await tester.pumpAndSettle();
      presses += 1;
    }

    expect(find.text('home'), findsOneWidget);
    expect(
      presses,
      2,
      reason: 'the list, then the screen it was opened from - and no more',
    );
  });

  testWidgets('the bell still closes the list it opened', (
    WidgetTester tester,
  ) async {
    await pump(tester);

    excursion.toggle('/notifications');
    await tester.pumpAndSettle();
    expect(find.text('notifications'), findsOneWidget);

    excursion.toggle('/notifications');
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(_depth(router), 1);
    expect(
      excursion.anchorDepth,
      isNull,
      reason: 'a closed excursion remembers nothing',
    );
  });

  testWidgets('a screen opened after walking back out is left alone', (
    WidgetTester tester,
  ) async {
    // The anchor must not outlive the excursion. A reader who backs out by
    // hand and then opens something else would otherwise have it closed under
    // them by the next press of the bell.
    await pump(tester);

    await readOne(tester, '1');

    router.pop();
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);

    router.push('/cart');
    await tester.pumpAndSettle();

    excursion.toggle('/notifications');
    await tester.pumpAndSettle();

    expect(find.text('notifications'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();

    expect(
      find.text('cart'),
      findsOneWidget,
      reason: 'the cart was not part of any excursion and must still be there',
    );
  });
}
