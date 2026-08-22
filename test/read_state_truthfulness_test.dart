import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/messages/bloc/chat_bloc.dart';
import 'package:merzox/features/messages/bloc/chat_event.dart';
import 'package:merzox/features/messages/bloc/chat_state.dart';
import 'package:merzox/features/notifications/bloc/notifications_bloc.dart';
import 'package:merzox/features/notifications/bloc/notifications_event.dart';
import 'package:merzox/features/notifications/bloc/notifications_state.dart';
import 'package:merzox/services/api_service.dart';

import 'auth_session_fixtures.dart';

/// These tests are all about the gap between "the UI says read" and "MongoDB
/// recorded read". A failed write must never close that gap silently.

MessageApiModel _message({String id = 'm1'}) => MessageApiModel(
  id: id,
  conversationId: 'c1',
  senderType: 'business',
  senderName: 'متجر الياسمين',
  body: 'هلا ، تفضلي؟',
  isMine: false,
  readAt: null,
  createdAt: DateTime.utc(2026, 2, 18, 9, 40),
);

AppNotificationApiModel _notification({
  required String id,
  bool isRead = false,
}) => AppNotificationApiModel(
  id: id,
  type: 'orderStatus',
  title: 'يتم تحضير طلبك',
  body: 'طلبك رقم MX-TEST-0001',
  data: const {'orderId': 'o1'},
  isRead: isRead,
  createdAt: DateTime.utc(2026, 2, 16, 9),
);

class _ChatApi extends ApiService {
  bool failMarkRead;
  int markReadCalls = 0;

  _ChatApi({this.failMarkRead = false});

  @override
  Future<ConversationMessagesApiResponse> conversationMessages({
    required String token,
    required String conversationId,
    int page = 1,
    int limit = 30,
  }) async {
    return ConversationMessagesApiResponse(
      conversation: ConversationApiModel.fromJson(const {
        'id': 'c1',
        'title': 'متجر الياسمين',
      }),
      messages: [_message()],
      page: page,
      hasMore: false,
    );
  }

  @override
  Future<ConversationApiModel> markConversationRead({
    required String token,
    required String conversationId,
  }) async {
    markReadCalls += 1;
    if (failMarkRead) throw StateError('read receipt refused');
    return ConversationApiModel.fromJson(const {'id': 'c1'});
  }
}

class _NotificationsApi extends ApiService {
  final List<AppNotificationApiModel> items;
  final int unread;
  bool failSingle;
  bool failAll;
  int singleCalls = 0;
  int allCalls = 0;

  _NotificationsApi({
    required this.items,
    required this.unread,
    this.failSingle = false,
    this.failAll = false,
  });

  @override
  Future<NotificationListApiResponse> notifications({
    required String token,
    bool businessAudience = false,
    bool unreadOnly = false,
    int page = 1,
    int limit = 20,
  }) async {
    return NotificationListApiResponse(
      notifications: items,
      unreadCount: unread,
      page: page,
      hasMore: false,
    );
  }

  @override
  Future<void> markNotificationRead({
    required String token,
    required String notificationId,
  }) async {
    singleCalls += 1;
    if (failSingle) throw StateError('write refused');
  }

  @override
  Future<void> markAllNotificationsRead({
    required String token,
    bool businessAudience = false,
  }) async {
    allCalls += 1;
    if (failAll) throw StateError('bulk write refused');
  }
}

Future<NotificationsBloc> _readyNotifications(_NotificationsApi api) async {
  final bloc = NotificationsBloc(apiService: api);
  bloc.add(const NotificationsStarted());
  await bloc.stream.firstWhere(
    (state) => state.status == NotificationsStatus.ready,
  );
  return bloc;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(useAuthenticatedSession);

  group('chat read synchronisation', () {
    test('a failed mark-read keeps the messages visible', () async {
      final api = _ChatApi(failMarkRead: true);
      final bloc = ChatBloc(apiService: api, conversationId: 'c1');

      bloc.add(const ChatStarted());
      await bloc.stream.firstWhere((state) => state.readSyncFailed);

      // The thread is still usable: only the receipt failed.
      expect(bloc.state.status, ChatStatus.ready);
      expect(bloc.state.messages, hasLength(1));
      expect(bloc.state.errorMessage, isEmpty);

      await bloc.close();
    });

    test('a failed mark-read is observable, not swallowed', () async {
      final api = _ChatApi(failMarkRead: true);
      final bloc = ChatBloc(apiService: api, conversationId: 'c1');

      bloc.add(const ChatStarted());
      await bloc.stream.firstWhere((state) => state.readSyncFailed);

      expect(bloc.state.readSyncFailed, isTrue);
      expect(api.markReadCalls, 1);

      await bloc.close();
    });

    test('a successful mark-read leaves no synchronisation error', () async {
      final api = _ChatApi();
      final bloc = ChatBloc(apiService: api, conversationId: 'c1');

      bloc.add(const ChatStarted());
      await bloc.stream.firstWhere((state) => state.status == ChatStatus.ready);
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.readSyncFailed, isFalse);
      expect(api.markReadCalls, 1);

      await bloc.close();
    });

    test('a later success clears an earlier synchronisation failure', () async {
      final api = _ChatApi(failMarkRead: true);
      final bloc = ChatBloc(apiService: api, conversationId: 'c1');

      bloc.add(const ChatStarted());
      await bloc.stream.firstWhere((state) => state.readSyncFailed);

      api.failMarkRead = false;
      bloc.add(const ChatRefreshRequested());
      await bloc.stream.firstWhere(
        (state) => state.status == ChatStatus.ready && !state.readSyncFailed,
      );

      expect(bloc.state.readSyncFailed, isFalse);
      expect(bloc.state.messages, hasLength(1));

      await bloc.close();
    });
  });

  group('single notification read', () {
    test('a successful write leaves the row read', () async {
      final api = _NotificationsApi(
        items: [
          _notification(id: 'n1'),
          _notification(id: 'n2'),
        ],
        unread: 2,
      );
      final bloc = await _readyNotifications(api);

      bloc.add(const NotificationMarkedRead('n1'));
      await bloc.stream.firstWhere((state) => state.notifications.first.isRead);
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.notifications.first.isRead, isTrue);
      expect(bloc.state.notifications.last.isRead, isFalse);
      expect(bloc.state.unreadCount, 1);
      expect(bloc.state.errorMessage, isEmpty);
      expect(api.singleCalls, 1);

      await bloc.close();
    });

    test('a failed write does not leave a false read state', () async {
      final api = _NotificationsApi(
        items: [
          _notification(id: 'n1'),
          _notification(id: 'n2'),
        ],
        unread: 2,
        failSingle: true,
      );
      final bloc = await _readyNotifications(api);

      bloc.add(const NotificationMarkedRead('n1'));
      await bloc.stream.firstWhere((state) => state.errorMessage.isNotEmpty);

      // Rolled back to exactly what MongoDB still holds.
      expect(bloc.state.notifications.first.isRead, isFalse);
      expect(bloc.state.unreadCount, 2);
      expect(api.singleCalls, 1);

      await bloc.close();
    });

    test('a rollback reverts only the affected row', () async {
      final api = _NotificationsApi(
        items: [
          _notification(id: 'n1'),
          _notification(id: 'n2', isRead: true),
        ],
        unread: 1,
      );
      final bloc = await _readyNotifications(api);

      api.failSingle = true;
      bloc.add(const NotificationMarkedRead('n1'));
      await bloc.stream.firstWhere((state) => state.errorMessage.isNotEmpty);

      expect(bloc.state.notifications.first.isRead, isFalse);
      // The already-read row is untouched by the rollback.
      expect(bloc.state.notifications.last.isRead, isTrue);
      expect(bloc.state.unreadCount, 1);

      await bloc.close();
    });

    test('the unread count never falls below zero', () async {
      final api = _NotificationsApi(
        items: [_notification(id: 'n1')],
        unread: 0,
      );
      final bloc = await _readyNotifications(api);

      bloc.add(const NotificationMarkedRead('n1'));
      await bloc.stream.firstWhere((state) => state.notifications.first.isRead);

      expect(bloc.state.unreadCount, 0);

      await bloc.close();
    });
  });

  group('mark all notifications read', () {
    test('a successful bulk write marks every row read', () async {
      final api = _NotificationsApi(
        items: [
          _notification(id: 'n1'),
          _notification(id: 'n2'),
        ],
        unread: 2,
      );
      final bloc = await _readyNotifications(api);

      bloc.add(const NotificationsAllMarkedRead());
      await bloc.stream.firstWhere((state) => state.unreadCount == 0);
      await Future<void>.delayed(Duration.zero);

      expect(
        bloc.state.notifications.every((notification) => notification.isRead),
        isTrue,
      );
      expect(bloc.state.errorMessage, isEmpty);
      expect(api.allCalls, 1);

      await bloc.close();
    });

    test('a failed bulk write restores the truthful state', () async {
      final api = _NotificationsApi(
        items: [
          _notification(id: 'n1'),
          _notification(id: 'n2', isRead: true),
        ],
        unread: 1,
        failAll: true,
      );
      final bloc = await _readyNotifications(api);

      bloc.add(const NotificationsAllMarkedRead());
      await bloc.stream.firstWhere((state) => state.errorMessage.isNotEmpty);

      // Nothing may look read that the server did not record.
      expect(bloc.state.notifications.first.isRead, isFalse);
      expect(bloc.state.notifications.last.isRead, isTrue);
      expect(bloc.state.unreadCount, 1);
      expect(api.allCalls, 1);

      await bloc.close();
    });

    test('a second bulk write is not fired while one is in flight', () async {
      final api = _NotificationsApi(
        items: [_notification(id: 'n1')],
        unread: 1,
      );
      final bloc = await _readyNotifications(api);

      bloc
        ..add(const NotificationsAllMarkedRead())
        ..add(const NotificationsAllMarkedRead());
      await bloc.stream.firstWhere((state) => state.unreadCount == 0);
      await Future<void>.delayed(Duration.zero);

      expect(api.allCalls, 1);

      await bloc.close();
    });
  });
}
