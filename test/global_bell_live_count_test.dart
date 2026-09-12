import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/notifications/widgets/global_notification_bell.dart';
import 'package:merzox/injection/injector.dart';
import 'package:merzox/services/realtime_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'localization_test_harness.dart';

/// Whether the bell is plugged into the socket that is supposed to move it.
///
/// It was not. The badge bloc takes the two realtime streams as arguments and
/// subscribes to whatever it is handed; the bell built it with its audience
/// and nothing else, so it was handed null twice and listened to nothing. The
/// count was read once, when the bell was first built, and then never again.
///
/// That one omission is both of the faults reported from a phone: a merchant
/// taking an order saw no bell move until the app was restarted, and reading a
/// notification left the number beside the bell exactly where it was. The
/// server was publishing `notification-created` and `notification-read` the
/// whole time, and nothing in the app was listening.
///
/// Every other test of this bell passes `blocBuilder`, which is why the gap
/// survived: none of them ever ran the construction the app runs. This one
/// deliberately does not pass it.
class _WatchedRealtime extends RealtimeService {
  final StreamController<RealtimeNotificationInvalidation> notifications =
      StreamController<RealtimeNotificationInvalidation>.broadcast();

  final StreamController<RealtimeConnectionStatus> statuses =
      StreamController<RealtimeConnectionStatus>.broadcast();

  @override
  Stream<RealtimeNotificationInvalidation> get notificationInvalidations =>
      notifications.stream;

  @override
  Stream<RealtimeConnectionStatus> get connectionStatuses => statuses.stream;

  Future<void> shutdown() async {
    await notifications.close();
    await statuses.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _WatchedRealtime realtime;

  setUpAll(() async {
    await loadAppTranslations();
  });

  setUp(() {
    // The badge reads a token the moment it starts. Without this the read
    // throws inside the bloc rather than in the test, which is harmless but
    // noisy.
    SharedPreferences.setMockInitialValues(const <String, Object>{});

    realtime = _WatchedRealtime();
    locator.registerSingleton<RealtimeService>(realtime);
  });

  tearDown(() async {
    await locator.reset();
    await realtime.shutdown();
  });

  Future<void> pumpBell(WidgetTester tester, {required bool business}) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.rtl,
        child: MediaQuery(
          data: const MediaQueryData(),
          // No blocBuilder. The point is the bloc the app itself builds.
          child: GlobalNotificationBell(
            businessAudience: business,
            onOpen: (String _) {},
          ),
        ),
      ),
    );
    await settleFrames(tester);
  }

  testWidgets('a merchant bell listens for notifications as they arrive', (
    WidgetTester tester,
  ) async {
    await pumpBell(tester, business: true);

    expect(
      realtime.notifications.hasListener,
      isTrue,
      reason:
          'the bell built a badge that subscribed to nothing, so an order '
          'arriving moves no number until the app is restarted',
    );
  });

  testWidgets('and a customer bell does too', (WidgetTester tester) async {
    await pumpBell(tester, business: false);

    expect(realtime.notifications.hasListener, isTrue);
  });

  testWidgets('it also watches the connection, so a reconnect catches up', (
    WidgetTester tester,
  ) async {
    // A socket that dropped and came back has missed every event in between.
    // The badge re-reads the count on reconnect, which is only possible if it
    // is told about the connection at all.
    await pumpBell(tester, business: true);

    expect(
      realtime.statuses.hasListener,
      isTrue,
      reason: 'a bell that misses a reconnect stays stale until it is rebuilt',
    );
  });

  testWidgets('a bell built with no realtime service registered still works', (
    WidgetTester tester,
  ) async {
    // The bell hangs above the router and has no provider tree over it, so it
    // reads the locator. A test - or a startup that failed halfway - may have
    // nothing registered, and the app root is the last place that should throw.
    await locator.reset();

    await pumpBell(tester, business: true);

    expect(tester.takeException(), isNull);
    expect(find.byType(GlobalNotificationBell), findsOneWidget);
  });
}
