import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/features/messages/bloc/message_badge_bloc.dart';
import 'package:merzox/features/messages/widgets/message_badge.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/services/realtime_service.dart';

import 'localization_test_harness.dart';

/// How many people are waiting on a reply.
///
/// The messages icon said nothing at all: a merchant with four customers
/// waiting and a merchant with none saw the same outline, so the only way to
/// find out was to open the screen and look.
///
/// The number is conversations, not messages - four messages from one customer
/// is one person waiting, which is the thing being decided about.

class _ConversationsApi extends ApiService {
  int customerUnread;
  int businessUnread;
  int calls = 0;
  bool refuse = false;

  /// Which side each call asked for, so the two cannot be confused.
  final List<bool> asked = <bool>[];

  _ConversationsApi({this.customerUnread = 0, this.businessUnread = 0});

  @override
  Future<ConversationListApiResponse> conversations({
    required String token,
    bool unreadOnly = false,
    int page = 1,
    int limit = 20,
  }) async => _answer(business: false, limit: limit);

  @override
  Future<ConversationListApiResponse> merchantConversations({
    required String token,
    bool unreadOnly = false,
    int page = 1,
    int limit = 20,
  }) async => _answer(business: true, limit: limit);

  ConversationListApiResponse _answer({
    required bool business,
    required int limit,
  }) {
    calls += 1;
    asked.add(business);

    if (refuse) throw StateError('offline');

    return ConversationListApiResponse(
      conversations: const <ConversationApiModel>[],
      unreadConversationCount: business ? businessUnread : customerUnread,
      page: 1,
      hasMore: false,
    );
  }
}

class _Session implements AuthSessionService {
  final AuthSessionSnapshot snapshot;

  const _Session(this.snapshot);

  @override
  Future<AuthSessionSnapshot> read() async => snapshot;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const AuthSessionSnapshot _customer = AuthSessionSnapshot(
  type: AuthSessionType.customer,
  token: 'token',
);
const AuthSessionSnapshot _merchant = AuthSessionSnapshot(
  type: AuthSessionType.business,
  token: 'token',
);

MessageBadgeBloc _bloc(
  _ConversationsApi api, {
  bool businessAudience = false,
  AuthSessionSnapshot? session,
  Stream<RealtimeMessageInvalidation>? messages,
  Stream<RealtimeConnectionStatus>? connections,
}) => MessageBadgeBloc(
  apiService: api,
  authSessionService: _Session(
    session ?? (businessAudience ? _merchant : _customer),
  ),
  businessAudience: businessAudience,
  realtimeMessageInvalidations: messages,
  realtimeConnectionStatuses: connections,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  group('the count', () {
    test('a customer reads their own waiting conversations', () async {
      final _ConversationsApi api = _ConversationsApi(
        customerUnread: 3,
        businessUnread: 9,
      );
      final MessageBadgeBloc bloc = _bloc(api);
      addTearDown(bloc.close);

      bloc.add(const MessageBadgeStarted());
      await bloc.stream.firstWhere((MessageBadgeState s) => s.unreadCount > 0);

      expect(bloc.state.unreadCount, 3);
      expect(api.asked, <bool>[false], reason: 'it asked the wrong side');
    });

    test('a merchant reads the shop own', () async {
      final _ConversationsApi api = _ConversationsApi(
        customerUnread: 3,
        businessUnread: 9,
      );
      final MessageBadgeBloc bloc = _bloc(api, businessAudience: true);
      addTearDown(bloc.close);

      bloc.add(const MessageBadgeStarted());
      await bloc.stream.firstWhere((MessageBadgeState s) => s.unreadCount > 0);

      expect(bloc.state.unreadCount, 9);
      expect(api.asked, <bool>[true]);
    });

    test('a customer session cannot ask for a shop count', () async {
      final _ConversationsApi api = _ConversationsApi(businessUnread: 9);
      final MessageBadgeBloc bloc = _bloc(
        api,
        businessAudience: true,
        session: _customer,
      );
      addTearDown(bloc.close);

      bloc.add(const MessageBadgeStarted());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Refused before the request is made, not after it comes back.
      expect(api.calls, 0);
      expect(bloc.state.unreadCount, 0);
    });

    test('a refusal keeps the count that was already proven', () async {
      final _ConversationsApi api = _ConversationsApi(customerUnread: 5);
      final MessageBadgeBloc bloc = _bloc(api);
      addTearDown(bloc.close);

      bloc.add(const MessageBadgeStarted());
      await bloc.stream.firstWhere((MessageBadgeState s) => s.unreadCount == 5);

      // A refresh that failed is not evidence that nobody is waiting.
      api.refuse = true;
      bloc.add(const MessageBadgeSyncRequested());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.unreadCount, 5);
    });
  });

  group('keeping up', () {
    test('a message on the socket re-reads the count', () async {
      final StreamController<RealtimeMessageInvalidation> socket =
          StreamController<RealtimeMessageInvalidation>.broadcast();
      addTearDown(socket.close);

      final _ConversationsApi api = _ConversationsApi(customerUnread: 1);
      final MessageBadgeBloc bloc = _bloc(api, messages: socket.stream);
      addTearDown(bloc.close);

      bloc.add(const MessageBadgeStarted());
      await bloc.stream.firstWhere((MessageBadgeState s) => s.unreadCount == 1);

      // The socket says a conversation changed, never how many are unread now,
      // so the count is re-read rather than adjusted.
      api.customerUnread = 2;
      socket.add(
        const RealtimeMessageInvalidation(
          conversationId: 'c1',
          businessId: 'b1',
          reason: 'message',
        ),
      );

      await bloc.stream.firstWhere((MessageBadgeState s) => s.unreadCount == 2);
      expect(bloc.state.unreadCount, 2);
    });

    test('a reconnection re-reads a count that went stale offline', () async {
      final StreamController<RealtimeConnectionStatus> link =
          StreamController<RealtimeConnectionStatus>.broadcast();
      addTearDown(link.close);

      final _ConversationsApi api = _ConversationsApi(customerUnread: 1);
      final MessageBadgeBloc bloc = _bloc(api, connections: link.stream);
      addTearDown(bloc.close);

      bloc.add(const MessageBadgeStarted());
      await bloc.stream.firstWhere((MessageBadgeState s) => s.unreadCount == 1);

      api.customerUnread = 7;
      link.add(RealtimeConnectionStatus.connected);

      await bloc.stream.firstWhere((MessageBadgeState s) => s.unreadCount == 7);
      expect(bloc.state.unreadCount, 7);
    });
  });

  group('on the icon', () {
    testWidgets('the number sits on the icon it belongs to', (
      WidgetTester tester,
    ) async {
      await pumpLocalized(
        tester,
        Scaffold(
          body: MessageBadge(
            businessAudience: true,
            blocBuilder: () => _bloc(
              _ConversationsApi(businessUnread: 4),
              businessAudience: true,
            ),
            child: const Icon(Icons.chat_bubble_outline_rounded),
          ),
        ),
      );
      await settleFrames(tester);

      expect(find.text('4'), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);
    });

    testWidgets('nobody waiting draws no number, only the icon', (
      WidgetTester tester,
    ) async {
      await pumpLocalized(
        tester,
        Scaffold(
          body: MessageBadge(
            businessAudience: false,
            blocBuilder: () => _bloc(_ConversationsApi()),
            child: const Icon(Icons.chat_bubble_outline_rounded),
          ),
        ),
      );
      await settleFrames(tester);

      expect(
        find.byKey(const ValueKey<String>('merzox.unreadCount')),
        findsNothing,
      );
      expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);
    });

    testWidgets('it wears the same count the bell wears', (
      WidgetTester tester,
    ) async {
      // Two counts on one screen must not come to look like two different
      // kinds of thing.
      await pumpLocalized(
        tester,
        Scaffold(
          body: MessageBadge(
            businessAudience: false,
            blocBuilder: () => _bloc(_ConversationsApi(customerUnread: 128)),
            child: const Icon(Icons.chat_bubble_outline_rounded),
          ),
        ),
      );
      await settleFrames(tester);

      expect(find.text('99+'), findsOneWidget);
    });
  });
}
