import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:merzox/core/startup/startup_destination.dart';
import 'package:merzox/features/notifications/widgets/global_notification_bell.dart';
import 'package:merzox/app/app.dart';
import 'package:merzox/router/app_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reading the current location at the moment the app starts.
///
/// The global notification bell is mounted in `MaterialApp.router`'s builder,
/// and that builder runs on the very first frame - before the router has
/// resolved anything. `GoRouter.state` reads the last of an empty match list
/// there and throws `Bad state: No element`, which the framework paints as a
/// red screen. It happened on every launch, before any screen was reached.
///
/// So what is under test is not which location comes back but that asking for
/// one at all is safe before the first route exists.

GoRouter _routerAt(StartupDestination destination) {
  final GoRouter router = AppRouter(destination).router;
  addTearDown(router.dispose);
  return router;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the location can be read before the first route is resolved', () {
    for (final StartupDestination destination in StartupDestination.values) {
      final GoRouter router = _routerAt(destination);

      // Nothing has been navigated to yet. This is exactly the moment the
      // builder runs on.
      expect(
        () => router.routeInformationProvider.value.uri.toString(),
        returnsNormally,
        reason: 'launching at $destination cannot report where it is',
      );
    }
  });

  test('what comes back is a location the bell can be asked about', () {
    for (final StartupDestination destination in StartupDestination.values) {
      final GoRouter router = _routerAt(destination);
      final String location = router.routeInformationProvider.value.uri
          .toString();

      expect(location, startsWith('/'), reason: '$destination');
      expect(
        () => globalBellWantedAt(location),
        returnsNormally,
        reason: '$destination',
      );
    }
  });

  test('the router is not asked the question that throws', () {
    // `GoRouter.state` is the way this broke. Kept as a statement of the
    // reason rather than a warning in a comment: if it ever stops throwing
    // here, the safer reading below is no longer needed.
    final GoRouter router = _routerAt(StartupDestination.onboarding);

    expect(() => router.state, throwsStateError);
    expect(() => router.routeInformationProvider.value, returnsNormally);
  });

  testWidgets('the app root paints its first frame instead of an error', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    for (final StartupDestination destination in StartupDestination.values) {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          EasyLocalization(
            supportedLocales: const <Locale>[Locale('en'), Locale('ar')],
            path: 'assets/translations',
            fallbackLocale: const Locale('ar'),
            startLocale: const Locale('ar'),
            saveLocale: false,
            child: MerzoxApp(
              key: ValueKey<String>('$destination'),
              destination: destination,
            ),
          ),
        );
        await tester.idle();
        await tester.pump();
      });

      // The whole bug: a red screen on every launch, before any screen.
      expect(
        tester.takeException(),
        isNull,
        reason: 'launching at $destination paints an error screen',
      );
    }
  });
}
