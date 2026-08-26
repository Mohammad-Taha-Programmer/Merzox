import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/features/notifications/bloc/notification_badge_bloc.dart';
import 'package:merzox/features/notifications/bloc/notification_badge_event.dart';
import 'package:merzox/features/notifications/bloc/notification_badge_state.dart';
import 'package:merzox/features/notifications/widgets/notification_badge_button.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/services/realtime_service.dart';

class _BadgeSessionService extends AuthSessionService {
  final AuthSessionSnapshot snapshot;

  const _BadgeSessionService(this.snapshot);

  @override
  Future<AuthSessionSnapshot> read() async => snapshot;
}

class _BadgeApi extends ApiService {
  int unreadCount = 0;
  int calls = 0;

  final List<bool> audienceFlags = [];

  @override
  Future<int> notificationUnreadCount({
    required String token,
    bool businessAudience = false,
  }) async {
    calls += 1;
    audienceFlags.add(businessAudience);

    return unreadCount;
  }
}

void main() {
  test('customer badge loads customer unread truth', () async {
    final api = _BadgeApi()..unreadCount = 4;

    final bloc = NotificationBadgeBloc(
      apiService: api,
      authSessionService: const _BadgeSessionService(
        AuthSessionSnapshot(type: AuthSessionType.customer, token: 'token'),
      ),
    );

    addTearDown(bloc.close);

    bloc.add(const NotificationBadgeStarted());

    await bloc.stream.firstWhere(
      (state) => state.status == NotificationBadgeStatus.ready,
    );

    expect(bloc.state.unreadCount, 4);

    expect(api.audienceFlags, [false]);
  });

  test('business badge uses business audience', () async {
    final api = _BadgeApi()..unreadCount = 2;

    final bloc = NotificationBadgeBloc(
      apiService: api,
      authSessionService: const _BadgeSessionService(
        AuthSessionSnapshot(type: AuthSessionType.business, token: 'token'),
      ),
      businessAudience: true,
    );

    addTearDown(bloc.close);

    bloc.add(const NotificationBadgeStarted());

    await bloc.stream.firstWhere(
      (state) => state.status == NotificationBadgeStatus.ready,
    );

    expect(bloc.state.unreadCount, 2);

    expect(api.audienceFlags, [true]);
  });

  test('customer session cannot claim business badge audience', () async {
    final api = _BadgeApi();

    final bloc = NotificationBadgeBloc(
      apiService: api,
      authSessionService: const _BadgeSessionService(
        AuthSessionSnapshot(type: AuthSessionType.customer, token: 'token'),
      ),
      businessAudience: true,
    );

    addTearDown(bloc.close);

    bloc.add(const NotificationBadgeStarted());

    await bloc.stream.firstWhere(
      (state) => state.status == NotificationBadgeStatus.failure,
    );

    expect(api.calls, 0);
  });

  test('realtime refresh is audience isolated', () async {
    final invalidations =
        StreamController<RealtimeNotificationInvalidation>.broadcast();

    addTearDown(invalidations.close);

    final api = _BadgeApi()..unreadCount = 1;

    final bloc = NotificationBadgeBloc(
      apiService: api,
      authSessionService: const _BadgeSessionService(
        AuthSessionSnapshot(type: AuthSessionType.customer, token: 'token'),
      ),
      realtimeNotificationInvalidations: invalidations.stream,
    );

    addTearDown(bloc.close);

    bloc.add(const NotificationBadgeStarted());

    await bloc.stream.firstWhere(
      (state) => state.status == NotificationBadgeStatus.ready,
    );

    expect(api.calls, 1);

    invalidations.add(
      const RealtimeNotificationInvalidation(
        audience: 'business',
        reason: 'notification-created',
        notificationId: 'b1',
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 180));

    expect(api.calls, 1);

    api.unreadCount = 3;

    invalidations.add(
      const RealtimeNotificationInvalidation(
        audience: 'customer',
        reason: 'notification-created',
        notificationId: 'c1',
      ),
    );

    await bloc.stream.firstWhere((state) => state.unreadCount == 3);

    expect(api.calls, 2);
  });

  test('reconnect refreshes badge from REST truth', () async {
    final connections = StreamController<RealtimeConnectionStatus>.broadcast();

    addTearDown(connections.close);

    final api = _BadgeApi()..unreadCount = 1;

    final bloc = NotificationBadgeBloc(
      apiService: api,
      authSessionService: const _BadgeSessionService(
        AuthSessionSnapshot(type: AuthSessionType.customer, token: 'token'),
      ),
      realtimeConnectionStatuses: connections.stream,
    );

    addTearDown(bloc.close);

    bloc.add(const NotificationBadgeStarted());

    await bloc.stream.firstWhere(
      (state) => state.status == NotificationBadgeStatus.ready,
    );

    api.unreadCount = 5;

    connections.add(RealtimeConnectionStatus.disconnected);

    connections.add(RealtimeConnectionStatus.connected);

    await bloc.stream.firstWhere((state) => state.unreadCount == 5);

    expect(api.calls, 2);
  });

  testWidgets('badge dot is rendered only when unread count is positive', (
    tester,
  ) async {
    final api = _BadgeApi()..unreadCount = 2;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationBadgeButton(
            tooltip: 'Notifications',
            onPressed: () {},
            apiService: api,
            authSessionService: const _BadgeSessionService(
              AuthSessionSnapshot(
                type: AuthSessionType.customer,
                token: 'token',
              ),
            ),
            realtimeNotificationInvalidations:
                const Stream<RealtimeNotificationInvalidation>.empty(),
            realtimeConnectionStatuses:
                const Stream<RealtimeConnectionStatus>.empty(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('notification-unread-dot')),
      findsOneWidget,
    );
  });

  testWidgets('zero unread count renders no fake notification dot', (
    tester,
  ) async {
    final api = _BadgeApi()..unreadCount = 0;

    var pressed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationBadgeButton(
            tooltip: 'Notifications',
            onPressed: () {
              pressed = true;
            },
            apiService: api,
            authSessionService: const _BadgeSessionService(
              AuthSessionSnapshot(
                type: AuthSessionType.customer,
                token: 'token',
              ),
            ),
            realtimeNotificationInvalidations:
                const Stream<RealtimeNotificationInvalidation>.empty(),
            realtimeConnectionStatuses:
                const Stream<RealtimeConnectionStatus>.empty(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('notification-unread-dot')), findsNothing);

    await tester.tap(find.byTooltip('Notifications'));

    expect(pressed, isTrue);
  });
}
