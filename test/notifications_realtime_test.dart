import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/features/notifications/bloc/notifications_bloc.dart';
import 'package:merzox/features/notifications/bloc/notifications_event.dart';
import 'package:merzox/features/notifications/bloc/notifications_state.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/services/realtime_service.dart';

class _SessionService extends AuthSessionService {
  final AuthSessionSnapshot snapshot;

  const _SessionService(this.snapshot);

  @override
  Future<AuthSessionSnapshot> read() async => snapshot;
}

AppNotificationApiModel _notification({
  String id = 'n1',
  String body = 'old',
  bool isRead = false,
}) {
  return AppNotificationApiModel(
    id: id,
    type: 'orderStatus',
    title: 'Notification',
    body: body,
    data: const {},
    isRead: isRead,
    createdAt: DateTime.utc(2026, 8, 26),
  );
}

class _NotificationApi extends ApiService {
  int listCalls = 0;
  int readCalls = 0;
  int allReadCalls = 0;

  Completer<void>? markReadCompleter;

  NotificationListApiResponse Function(
    bool businessAudience,
    int page,
    int call,
  )?
  onList;

  @override
  Future<NotificationListApiResponse> notifications({
    required String token,
    bool businessAudience = false,
    bool unreadOnly = false,
    int page = 1,
    int limit = 20,
  }) async {
    listCalls += 1;

    return onList?.call(businessAudience, page, listCalls) ??
        NotificationListApiResponse(
          notifications: [_notification()],
          unreadCount: 1,
          page: page,
          hasMore: false,
        );
  }

  @override
  Future<void> markNotificationRead({
    required String token,
    required String notificationId,
  }) async {
    readCalls += 1;

    final completer = markReadCompleter;

    if (completer != null) {
      await completer.future;
    }
  }

  @override
  Future<void> markAllNotificationsRead({
    required String token,
    bool businessAudience = false,
  }) async {
    allReadCalls += 1;
  }
}

void main() {
  test(
    'customer realtime notification refreshes authoritative page one',
    () async {
      final invalidations =
          StreamController<RealtimeNotificationInvalidation>.broadcast();

      addTearDown(invalidations.close);

      final api = _NotificationApi()
        ..onList = (businessAudience, page, call) =>
            NotificationListApiResponse(
              notifications: [_notification(body: call == 1 ? 'old' : 'live')],
              unreadCount: call == 1 ? 0 : 1,
              page: page,
              hasMore: false,
            );

      final bloc = NotificationsBloc(
        apiService: api,
        authSessionService: const _SessionService(
          AuthSessionSnapshot(type: AuthSessionType.customer, token: 'token'),
        ),
        realtimeNotificationInvalidations: invalidations.stream,
      );

      addTearDown(bloc.close);

      bloc.add(const NotificationsStarted());

      await bloc.stream.firstWhere(
        (state) => state.status == NotificationsStatus.ready,
      );

      invalidations.add(
        const RealtimeNotificationInvalidation(
          audience: 'customer',
          reason: 'notification-created',
          notificationId: 'n2',
        ),
      );

      await bloc.stream.firstWhere(
        (state) =>
            state.status == NotificationsStatus.ready &&
            state.notifications.single.body == 'live',
      );

      expect(api.listCalls, 2);
      expect(bloc.state.unreadCount, 1);
      expect(bloc.state.page, 1);
    },
  );

  test(
    'business feed ignores customer invalidation and accepts business one',
    () async {
      final invalidations =
          StreamController<RealtimeNotificationInvalidation>.broadcast();

      addTearDown(invalidations.close);

      final api = _NotificationApi();

      final bloc = NotificationsBloc(
        apiService: api,
        authSessionService: const _SessionService(
          AuthSessionSnapshot(type: AuthSessionType.business, token: 'token'),
        ),
        businessAudience: true,
        realtimeNotificationInvalidations: invalidations.stream,
      );

      addTearDown(bloc.close);

      bloc.add(const NotificationsStarted());

      await bloc.stream.firstWhere(
        (state) => state.status == NotificationsStatus.ready,
      );

      expect(api.listCalls, 1);

      invalidations.add(
        const RealtimeNotificationInvalidation(
          audience: 'customer',
          reason: 'notification-created',
          notificationId: 'customer-n',
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 180));

      expect(api.listCalls, 1);

      invalidations.add(
        const RealtimeNotificationInvalidation(
          audience: 'business',
          reason: 'notification-created',
          notificationId: 'business-n',
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 180));

      expect(api.listCalls, 2);
    },
  );

  test('reconnect refreshes notification feed from REST', () async {
    final connections = StreamController<RealtimeConnectionStatus>.broadcast();

    addTearDown(connections.close);

    final api = _NotificationApi();

    final bloc = NotificationsBloc(
      apiService: api,
      authSessionService: const _SessionService(
        AuthSessionSnapshot(type: AuthSessionType.customer, token: 'token'),
      ),
      realtimeConnectionStatuses: connections.stream,
    );

    addTearDown(bloc.close);

    bloc.add(const NotificationsStarted());

    await bloc.stream.firstWhere(
      (state) => state.status == NotificationsStatus.ready,
    );

    connections.add(RealtimeConnectionStatus.disconnected);

    connections.add(RealtimeConnectionStatus.connected);

    await Future<void>.delayed(const Duration(milliseconds: 180));

    expect(api.listCalls, 2);
  });

  test(
    'realtime refresh waits for optimistic single-read write to settle',
    () async {
      final invalidations =
          StreamController<RealtimeNotificationInvalidation>.broadcast();

      addTearDown(invalidations.close);

      final writeCompleter = Completer<void>();

      final api = _NotificationApi()
        ..markReadCompleter = writeCompleter
        ..onList = (businessAudience, page, call) =>
            NotificationListApiResponse(
              notifications: [_notification(isRead: call > 1)],
              unreadCount: call > 1 ? 0 : 1,
              page: page,
              hasMore: false,
            );

      final bloc = NotificationsBloc(
        apiService: api,
        authSessionService: const _SessionService(
          AuthSessionSnapshot(type: AuthSessionType.customer, token: 'token'),
        ),
        realtimeNotificationInvalidations: invalidations.stream,
      );

      addTearDown(bloc.close);

      bloc.add(const NotificationsStarted());

      await bloc.stream.firstWhere(
        (state) => state.status == NotificationsStatus.ready,
      );

      bloc.add(const NotificationMarkedRead('n1'));

      await bloc.stream.firstWhere(
        (state) => state.notifications.single.isRead,
      );

      invalidations.add(
        const RealtimeNotificationInvalidation(
          audience: 'customer',
          reason: 'notification-read',
          notificationId: 'n1',
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 180));

      // No REST refresh while the optimistic authoritative write is pending.
      expect(api.listCalls, 1);

      writeCompleter.complete();

      await Future<void>.delayed(const Duration(milliseconds: 220));

      expect(api.readCalls, 1);
      expect(api.listCalls, 2);
      expect(bloc.state.unreadCount, 0);
      expect(bloc.state.notifications.single.isRead, isTrue);
    },
  );
}
