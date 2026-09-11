import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:merzox/features/notifications/widgets/global_notification_bell.dart';

import 'localization_test_harness.dart';

/// The bell above the router has to follow the router.
///
/// It is mounted once, over every route, and whether it shows is decided from
/// the current location. Deciding is not the same as listening: the app's
/// builder used to read the location without subscribing to anything, so it
/// kept whichever answer it had when it last ran for some other reason. A
/// reader signed in, arrived at a home screen with no bell, and the bell
/// appeared when they pressed the language toggle - because changing the
/// locale is what finally rebuilt the app root.
///
/// [GlobalBellOverlay] is the widget the app ships, exercised here rather than
/// a copy of it: a test that rebuilt the arrangement would have proved only
/// that the test knows the answer.

/// Stands in for the bell, so this file is about the following and not about
/// what the bell draws.
const Key _bell = ValueKey<String>('test.bell');

Widget _host(GoRouter router) => MaterialApp.router(
  routerConfig: router,
  builder: (BuildContext context, Widget? child) => GlobalBellOverlay(
    router: router,
    bellBuilder: (BuildContext _) => const SizedBox(key: _bell, width: 24),
    child: child ?? const SizedBox.shrink(),
  ),
);

GoRouter _router() => GoRouter(
  initialLocation: '/login',
  routes: <RouteBase>[
    GoRoute(
      path: '/login',
      builder: (_, _) => const Scaffold(body: Text('login')),
    ),
    GoRoute(
      path: '/home',
      builder: (_, _) => const Scaffold(body: Text('home')),
      routes: <RouteBase>[
        GoRoute(
          path: 'notifications',
          builder: (_, _) => const Scaffold(body: Text('notifications')),
        ),
      ],
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('signing in brings it, with nothing else touched', (
    tester,
  ) async {
    final GoRouter router = _router();
    addTearDown(router.dispose);

    await tester.pumpWidget(_host(router));
    await settleFrames(tester);

    expect(
      find.byKey(_bell),
      findsNothing,
      reason: 'a bell over a login form is noise',
    );

    router.go('/home');
    await settleFrames(tester);

    expect(
      find.byKey(_bell),
      findsOneWidget,
      reason: 'navigation alone has to bring it',
    );
  });

  testWidgets('signing out takes it away again', (tester) async {
    final GoRouter router = _router();
    addTearDown(router.dispose);

    await tester.pumpWidget(_host(router));
    router.go('/home');
    await settleFrames(tester);
    expect(find.byKey(_bell), findsOneWidget);

    router.go('/login');
    await settleFrames(tester);

    expect(find.byKey(_bell), findsNothing);
  });

  testWidgets('a push keeps it, which is how it closes what it opened', (
    tester,
  ) async {
    // The route information provider does not move for a `push`, so listening
    // to that instead of the delegate would leave the bell answering about the
    // screen it was opened from.
    final GoRouter router = _router();
    addTearDown(router.dispose);

    await tester.pumpWidget(_host(router));
    router.go('/home');
    await settleFrames(tester);

    router.push('/home/notifications');
    await settleFrames(tester);

    expect(find.text('notifications'), findsOneWidget);
    expect(
      find.byKey(_bell),
      findsOneWidget,
      reason: 'the bell is how that screen is closed again',
    );
  });
}
