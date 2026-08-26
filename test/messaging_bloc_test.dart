import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/messages/bloc/chat_bloc.dart';
import 'package:merzox/features/messages/bloc/chat_event.dart';
import 'package:merzox/features/messages/bloc/chat_state.dart';
import 'package:merzox/features/messages/bloc/messages_bloc.dart';
import 'package:merzox/features/messages/bloc/messages_event.dart';
import 'package:merzox/features/messages/bloc/messages_state.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/services/realtime_service.dart';
import 'auth_session_fixtures.dart';

ConversationApiModel _conversation({
  String id = 'c1',
  String title = 'متجر الياسمين',
  String lastBody = 'متى المتجر بيفتح؟',
  int unreadCount = 0,
}) {
  return ConversationApiModel(
    id: id,
    title: title,
    avatarUrl: '',
    business: const ConversationPartyApiModel(
      id: 'b1',
      name: 'متجر الياسمين',
      logoUrl: '',
    ),
    customer: null,
    lastMessage: ConversationLastMessageApiModel(
      body: lastBody,
      senderType: 'customer',
      sentAt: DateTime.utc(2026, 2, 18, 9, 43),
    ),
    unreadCount: unreadCount,
    messageCount: 4,
    updatedAt: DateTime.utc(2026, 2, 18, 9, 43),
  );
}

MessageApiModel _message({
  String id = 'm1',
  String body = 'مرحبا ، عندي استفسار',
  bool isMine = true,
}) {
  return MessageApiModel(
    id: id,
    conversationId: 'c1',
    senderType: isMine ? 'customer' : 'business',
    senderName: isMine ? 'ياسمين خالد' : 'متجر الياسمين',
    body: body,
    isMine: isMine,
    readAt: null,
    createdAt: DateTime.utc(2026, 2, 18, 9, 40),
  );
}

class _FakeMessagingApi extends ApiService {
  final List<bool> customerUnreadFlags = [];
  final List<bool> merchantCalls = [];
  final List<String> sentBodies = [];
  final List<String> markedRead = [];
  final List<String> openedBusinessIds = [];
  final List<int> messagePages = [];

  ConversationListApiResponse Function(bool unreadOnly, int page)?
  onConversations;
  ConversationMessagesApiResponse Function(int page)? onMessages;
  Object? sendError;

  @override
  Future<ConversationListApiResponse> conversations({
    required String token,
    bool unreadOnly = false,
    int page = 1,
    int limit = 20,
  }) async {
    customerUnreadFlags.add(unreadOnly);
    return onConversations?.call(unreadOnly, page) ??
        const ConversationListApiResponse(
          conversations: [],
          unreadConversationCount: 0,
          page: 1,
          hasMore: false,
        );
  }

  @override
  Future<ConversationListApiResponse> merchantConversations({
    required String token,
    bool unreadOnly = false,
    int page = 1,
    int limit = 20,
  }) async {
    merchantCalls.add(unreadOnly);
    return onConversations?.call(unreadOnly, page) ??
        const ConversationListApiResponse(
          conversations: [],
          unreadConversationCount: 0,
          page: 1,
          hasMore: false,
        );
  }

  @override
  Future<ConversationApiModel> openConversation({
    required String token,
    required String businessId,
  }) async {
    openedBusinessIds.add(businessId);
    return _conversation();
  }

  @override
  Future<ConversationMessagesApiResponse> conversationMessages({
    required String token,
    required String conversationId,
    int page = 1,
    int limit = 30,
  }) async {
    messagePages.add(page);

    return onMessages?.call(page) ??
        ConversationMessagesApiResponse(
          conversation: _conversation(),
          messages: [_message()],
          page: page,
          hasMore: false,
        );
  }

  @override
  Future<MessageApiModel> sendMessage({
    required String token,
    required String conversationId,
    required String body,
  }) async {
    if (sendError != null) throw sendError!;
    sentBodies.add(body);
    return _message(id: 'm2', body: body);
  }

  @override
  Future<ConversationApiModel> markConversationRead({
    required String token,
    required String conversationId,
  }) async {
    markedRead.add(conversationId);
    return _conversation();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(useAuthenticatedSession);

  test('the inbox loads threads and reports the unread count', () async {
    final api = _FakeMessagingApi()
      ..onConversations = (_, page) => ConversationListApiResponse(
        conversations: [_conversation(unreadCount: 2)],
        unreadConversationCount: 1,
        page: page,
        hasMore: false,
      );
    final bloc = MessagesBloc(apiService: api);

    bloc.add(const MessagesStarted());
    await bloc.stream.firstWhere(
      (state) => state.status == MessagesStatus.ready,
    );

    expect(bloc.state.conversations, hasLength(1));
    expect(bloc.state.conversations.single.hasUnread, isTrue);
    expect(bloc.state.unreadConversationCount, 1);
    expect(api.customerUnreadFlags, [false]);

    await bloc.close();
  });

  test('the unread tab asks the API for unread threads only', () async {
    final api = _FakeMessagingApi()
      ..onConversations = (unreadOnly, page) => ConversationListApiResponse(
        conversations: unreadOnly ? [_conversation(unreadCount: 3)] : const [],
        unreadConversationCount: unreadOnly ? 1 : 0,
        page: page,
        hasMore: false,
      );
    final bloc = MessagesBloc(apiService: api);

    bloc.add(const MessagesStarted());
    await bloc.stream.firstWhere(
      (state) => state.status == MessagesStatus.ready,
    );

    bloc.add(const MessagesFilterChanged(MessagesFilter.unread));
    await bloc.stream.firstWhere(
      (state) =>
          state.status == MessagesStatus.ready &&
          state.filter == MessagesFilter.unread,
    );

    expect(api.customerUnreadFlags, [false, true]);
    expect(bloc.state.conversations, hasLength(1));

    await bloc.close();
  });

  test('a merchant inbox reads the merchant endpoint', () async {
    // Updated for the FIX2 contract: the merchant inbox is a different
    // endpoint, so it now requires a business session rather than any
    // authenticated one.
    useAuthenticatedSession(business: true);
    final api = _FakeMessagingApi();
    final bloc = MessagesBloc(apiService: api, merchantMode: true);

    bloc.add(const MessagesStarted());
    await bloc.stream.firstWhere(
      (state) => state.status == MessagesStatus.ready,
    );

    expect(api.merchantCalls, [false]);
    expect(api.customerUnreadFlags, isEmpty);

    await bloc.close();
  });

  test('a customer session cannot drive the merchant inbox', () async {
    // merchantMode is a construction flag, not a role. Without a business
    // session the bloc must fail before touching either endpoint.
    final api = _FakeMessagingApi();
    final bloc = MessagesBloc(apiService: api, merchantMode: true);

    bloc.add(const MessagesStarted());
    await bloc.stream.firstWhere(
      (state) => state.status == MessagesStatus.failure,
    );

    expect(api.merchantCalls, isEmpty);
    expect(api.customerUnreadFlags, isEmpty);

    await bloc.close();
  });

  // R2 §1: the inbox no longer zeroes an unread count locally. Whatever the
  // backend reports on refresh is what the badge shows, so a chat whose
  // mark-read failed keeps its unread state instead of appearing read.
  test(
    'CASE A: a confirmed read is reflected by the backend refresh',
    () async {
      var readOnServer = false;
      final api = _FakeMessagingApi()
        ..onConversations = (_, page) => ConversationListApiResponse(
          conversations: [
            _conversation(id: 'c1', unreadCount: readOnServer ? 0 : 2),
          ],
          unreadConversationCount: readOnServer ? 0 : 1,
          page: page,
          hasMore: false,
        );
      final bloc = MessagesBloc(apiService: api);

      bloc.add(const MessagesStarted());
      await bloc.stream.firstWhere(
        (state) => state.status == MessagesStatus.ready,
      );
      expect(bloc.state.conversations.single.unreadCount, 2);

      // The chat page persisted the receipt; the server now reports it read.
      readOnServer = true;
      bloc.add(const MessagesRefreshRequested());
      await bloc.stream.firstWhere(
        (state) =>
            state.status == MessagesStatus.ready &&
            state.conversations.single.unreadCount == 0,
      );

      expect(bloc.state.unreadConversationCount, 0);

      await bloc.close();
    },
  );

  test('CASE B: a failed mark-read leaves the badge untouched', () async {
    // The server still reports the thread unread because the receipt never
    // landed. Nothing in the inbox may force it to zero.
    final api = _FakeMessagingApi()
      ..onConversations = (_, page) => ConversationListApiResponse(
        conversations: [_conversation(id: 'c1', unreadCount: 2)],
        unreadConversationCount: 1,
        page: page,
        hasMore: false,
      );
    final bloc = MessagesBloc(apiService: api);

    bloc.add(const MessagesStarted());
    await bloc.stream.firstWhere(
      (state) => state.status == MessagesStatus.ready,
    );

    // Returning from chat refreshes; it must not fabricate a read state.
    bloc.add(const MessagesRefreshRequested());
    await bloc.stream.firstWhere(
      (state) => state.status == MessagesStatus.ready,
    );

    expect(bloc.state.conversations.single.unreadCount, 2);
    expect(bloc.state.unreadConversationCount, 1);

    await bloc.close();
  });

  test('CASE C: the backend response is the only unread authority', () async {
    // An arbitrary server-reported count is adopted verbatim, including one
    // that grew while the chat page was open.
    var unread = 2;
    final api = _FakeMessagingApi()
      ..onConversations = (_, page) => ConversationListApiResponse(
        conversations: [_conversation(id: 'c1', unreadCount: unread)],
        unreadConversationCount: unread > 0 ? 1 : 0,
        page: page,
        hasMore: false,
      );
    final bloc = MessagesBloc(apiService: api);

    bloc.add(const MessagesStarted());
    await bloc.stream.firstWhere(
      (state) => state.status == MessagesStatus.ready,
    );

    unread = 5;
    bloc.add(const MessagesRefreshRequested());
    await bloc.stream.firstWhere(
      (state) =>
          state.status == MessagesStatus.ready &&
          state.conversations.single.unreadCount == 5,
    );

    await bloc.close();
  });

  test(
    'CASE D: the unread filter drops a thread only when the server does',
    () async {
      // Opening a chat must not remove a row from the unread tab on its own.
      var stillUnread = true;
      final api = _FakeMessagingApi()
        ..onConversations = (unreadOnly, page) => ConversationListApiResponse(
          conversations: stillUnread
              ? [_conversation(id: 'c1', unreadCount: 2)]
              : const [],
          unreadConversationCount: stillUnread ? 1 : 0,
          page: page,
          hasMore: false,
        );
      final bloc = MessagesBloc(apiService: api);

      bloc.add(const MessagesFilterChanged(MessagesFilter.unread));
      await bloc.stream.firstWhere(
        (state) =>
            state.status == MessagesStatus.ready &&
            state.filter == MessagesFilter.unread,
      );
      expect(bloc.state.conversations, hasLength(1));

      // Returning from chat with the receipt still unpersisted: row stays.
      bloc.add(const MessagesRefreshRequested());
      await bloc.stream.firstWhere(
        (state) => state.status == MessagesStatus.ready,
      );
      expect(bloc.state.conversations, hasLength(1));

      // Only once the server says it is read does the row leave the filter.
      stillUnread = false;
      bloc.add(const MessagesRefreshRequested());
      await bloc.stream.firstWhere(
        (state) =>
            state.status == MessagesStatus.ready && state.conversations.isEmpty,
      );

      await bloc.close();
    },
  );

  test('opening a thread loads history and marks it read', () async {
    final api = _FakeMessagingApi();
    final bloc = ChatBloc(apiService: api, conversationId: 'c1');

    bloc.add(const ChatStarted());
    await bloc.stream.firstWhere((state) => state.status == ChatStatus.ready);

    expect(bloc.state.messages, hasLength(1));
    expect(bloc.state.title, 'متجر الياسمين');
    await Future<void>.delayed(Duration.zero);
    expect(api.markedRead, ['c1']);

    await bloc.close();
  });

  test('a store entry point creates the thread before loading it', () async {
    final api = _FakeMessagingApi();
    final bloc = ChatBloc(apiService: api);

    bloc.add(const ChatOpenedForBusiness('b1'));
    await bloc.stream.firstWhere((state) => state.status == ChatStatus.ready);

    expect(api.openedBusinessIds, ['b1']);
    expect(bloc.state.conversationId, 'c1');

    await bloc.close();
  });

  test('a sent message is appended to the thread', () async {
    final api = _FakeMessagingApi();
    final bloc = ChatBloc(apiService: api, conversationId: 'c1');

    bloc.add(const ChatStarted());
    await bloc.stream.firstWhere((state) => state.status == ChatStatus.ready);

    bloc.add(const ChatMessageSent('  متى المتجر بيفتح ؟  '));
    await bloc.stream.firstWhere((state) => state.messages.length == 2);

    expect(api.sentBodies, ['متى المتجر بيفتح ؟']);
    expect(bloc.state.messages.last.body, 'متى المتجر بيفتح ؟');

    await bloc.close();
  });

  test('an empty message never reaches the API', () async {
    final api = _FakeMessagingApi();
    final bloc = ChatBloc(apiService: api, conversationId: 'c1');

    bloc.add(const ChatStarted());
    await bloc.stream.firstWhere((state) => state.status == ChatStatus.ready);

    bloc.add(const ChatMessageSent('   '));
    await Future<void>.delayed(Duration.zero);

    expect(api.sentBodies, isEmpty);
    expect(bloc.state.messages, hasLength(1));

    await bloc.close();
  });

  test(
    'a failed send surfaces the error and keeps the thread usable',
    () async {
      final api = _FakeMessagingApi()..sendError = StateError('offline');
      final bloc = ChatBloc(apiService: api, conversationId: 'c1');

      bloc.add(const ChatStarted());
      await bloc.stream.firstWhere((state) => state.status == ChatStatus.ready);

      bloc.add(const ChatMessageSent('مرحبا'));
      await bloc.stream.firstWhere((state) => state.errorMessage.isNotEmpty);

      expect(bloc.state.status, ChatStatus.ready);
      expect(bloc.state.messages, hasLength(1));

      await bloc.close();
    },
  );

  test(
    'realtime inbox invalidation refreshes authoritative page one',
    () async {
      final invalidations =
          StreamController<RealtimeMessageInvalidation>.broadcast();

      final connections =
          StreamController<RealtimeConnectionStatus>.broadcast();

      addTearDown(invalidations.close);
      addTearDown(connections.close);

      var calls = 0;

      final api = _FakeMessagingApi()
        ..onConversations = (_, page) {
          calls += 1;

          return ConversationListApiResponse(
            conversations: [
              _conversation(
                lastBody: calls == 1 ? 'old summary' : 'live summary',
                unreadCount: calls == 1 ? 0 : 1,
              ),
            ],
            unreadConversationCount: calls == 1 ? 0 : 1,
            page: page,
            hasMore: false,
          );
        };

      final bloc = MessagesBloc(
        apiService: api,
        realtimeMessageInvalidations: invalidations.stream,
        realtimeConnectionStatuses: connections.stream,
      );

      addTearDown(bloc.close);

      bloc.add(const MessagesStarted());

      await bloc.stream.firstWhere(
        (state) => state.status == MessagesStatus.ready,
      );

      invalidations.add(
        const RealtimeMessageInvalidation(
          conversationId: 'c1',
          businessId: 'b1',
          messageId: 'm-live',
          reason: 'message-created',
        ),
      );

      await bloc.stream.firstWhere(
        (state) =>
            state.status == MessagesStatus.ready &&
            state.conversations.isNotEmpty &&
            state.conversations.single.lastMessage.body == 'live summary',
      );

      expect(calls, 2);
      expect(bloc.state.unreadConversationCount, 1);
      expect(bloc.state.page, 1);
    },
  );

  test('reconnect re-syncs inbox from REST after a disconnect', () async {
    final connections = StreamController<RealtimeConnectionStatus>.broadcast();

    addTearDown(connections.close);

    var calls = 0;

    final api = _FakeMessagingApi()
      ..onConversations = (_, page) {
        calls += 1;

        return ConversationListApiResponse(
          conversations: [_conversation(lastBody: 'call-$calls')],
          unreadConversationCount: 0,
          page: page,
          hasMore: false,
        );
      };

    final bloc = MessagesBloc(
      apiService: api,
      realtimeConnectionStatuses: connections.stream,
    );

    addTearDown(bloc.close);

    bloc.add(const MessagesStarted());

    await bloc.stream.firstWhere(
      (state) => state.status == MessagesStatus.ready,
    );

    connections.add(RealtimeConnectionStatus.disconnected);

    connections.add(RealtimeConnectionStatus.connected);

    await bloc.stream.firstWhere(
      (state) =>
          state.status == MessagesStatus.ready &&
          state.conversations.single.lastMessage.body == 'call-2',
    );

    expect(calls, 2);
  });

  test(
    'chat realtime merge preserves loaded history and deduplicates overlap',
    () async {
      final invalidations =
          StreamController<RealtimeMessageInvalidation>.broadcast();

      addTearDown(invalidations.close);

      var firstPageCalls = 0;

      final api = _FakeMessagingApi()
        ..onMessages = (page) {
          if (page == 1) {
            firstPageCalls += 1;

            return ConversationMessagesApiResponse(
              conversation: _conversation(),
              messages: firstPageCalls == 1
                  ? [
                      _message(id: 'm2', body: 'middle'),
                      _message(
                        id: 'm3',
                        body: 'previous newest',
                        isMine: false,
                      ),
                    ]
                  : [
                      _message(
                        id: 'm3',
                        body: 'previous newest',
                        isMine: false,
                      ),
                      _message(id: 'm4', body: 'live newest', isMine: false),
                    ],
              page: 1,
              hasMore: true,
            );
          }

          return ConversationMessagesApiResponse(
            conversation: _conversation(),
            messages: [
              _message(id: 'm1', body: 'oldest'),
              _message(id: 'm2', body: 'middle'),
            ],
            page: 2,
            hasMore: false,
          );
        };

      final bloc = ChatBloc(
        apiService: api,
        conversationId: 'c1',
        realtimeMessageInvalidations: invalidations.stream,
      );

      addTearDown(bloc.close);

      bloc.add(const ChatStarted());

      await bloc.stream.firstWhere((state) => state.status == ChatStatus.ready);

      bloc.add(const ChatOlderMessagesRequested());

      await bloc.stream.firstWhere(
        (state) => state.status == ChatStatus.ready && state.page == 2,
      );

      expect(bloc.state.messages.map((message) => message.id).toList(), [
        'm1',
        'm2',
        'm3',
      ]);

      invalidations.add(
        const RealtimeMessageInvalidation(
          conversationId: 'c1',
          businessId: 'b1',
          messageId: 'm4',
          reason: 'message-created',
        ),
      );

      await bloc.stream.firstWhere(
        (state) => state.messages.any((message) => message.id == 'm4'),
      );

      final ids = bloc.state.messages.map((message) => message.id).toList();

      expect(ids, ['m1', 'm2', 'm3', 'm4']);

      expect(ids.toSet(), hasLength(ids.length));

      // Realtime page-one refresh must not forget that page two was already
      // loaded or resurrect a stale "has more" flag from page one.
      expect(bloc.state.page, 2);
      expect(bloc.state.hasMore, isFalse);

      expect(api.messagePages, [1, 2, 1]);
    },
  );

  test('chat ignores realtime invalidation for another conversation', () async {
    final invalidations =
        StreamController<RealtimeMessageInvalidation>.broadcast();

    addTearDown(invalidations.close);

    final api = _FakeMessagingApi();

    final bloc = ChatBloc(
      apiService: api,
      conversationId: 'c1',
      realtimeMessageInvalidations: invalidations.stream,
    );

    addTearDown(bloc.close);

    bloc.add(const ChatStarted());

    await bloc.stream.firstWhere((state) => state.status == ChatStatus.ready);

    expect(api.messagePages, [1]);

    invalidations.add(
      const RealtimeMessageInvalidation(
        conversationId: 'other',
        businessId: 'b1',
        messageId: 'm-other',
        reason: 'message-created',
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 180));

    expect(api.messagePages, [1]);
  });

  test(
    'conversation-read invalidation refreshes unread-filter inbox truth',
    () async {
      final invalidations =
          StreamController<RealtimeMessageInvalidation>.broadcast();

      addTearDown(invalidations.close);

      var stillUnread = true;

      final api = _FakeMessagingApi()
        ..onConversations = (unreadOnly, page) => ConversationListApiResponse(
          conversations: unreadOnly && stillUnread
              ? [_conversation(unreadCount: 2)]
              : const [],
          unreadConversationCount: stillUnread ? 1 : 0,
          page: page,
          hasMore: false,
        );

      final bloc = MessagesBloc(
        apiService: api,
        realtimeMessageInvalidations: invalidations.stream,
      );

      addTearDown(bloc.close);

      bloc.add(const MessagesFilterChanged(MessagesFilter.unread));

      await bloc.stream.firstWhere(
        (state) =>
            state.status == MessagesStatus.ready &&
            state.filter == MessagesFilter.unread,
      );

      expect(bloc.state.conversations, hasLength(1));

      stillUnread = false;

      invalidations.add(
        const RealtimeMessageInvalidation(
          conversationId: 'c1',
          businessId: 'b1',
          reason: 'conversation-read',
        ),
      );

      await bloc.stream.firstWhere(
        (state) =>
            state.status == MessagesStatus.ready && state.conversations.isEmpty,
      );

      expect(bloc.state.unreadConversationCount, 0);
    },
  );
}
