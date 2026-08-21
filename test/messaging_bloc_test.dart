import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/messages/bloc/chat_bloc.dart';
import 'package:merzox/features/messages/bloc/chat_event.dart';
import 'package:merzox/features/messages/bloc/chat_state.dart';
import 'package:merzox/features/messages/bloc/messages_bloc.dart';
import 'package:merzox/features/messages/bloc/messages_event.dart';
import 'package:merzox/features/messages/bloc/messages_state.dart';
import 'package:merzox/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  setUp(() {
    SharedPreferences.setMockInitialValues({AuthBloc.tokenKey: 'test-token'});
  });

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

  test('reading a thread clears its badge without a reload', () async {
    final api = _FakeMessagingApi()
      ..onConversations = (_, page) => ConversationListApiResponse(
        conversations: [
          _conversation(id: 'c1', unreadCount: 2),
          _conversation(id: 'c2', unreadCount: 1),
        ],
        unreadConversationCount: 2,
        page: page,
        hasMore: false,
      );
    final bloc = MessagesBloc(apiService: api);

    bloc.add(const MessagesStarted());
    await bloc.stream.firstWhere(
      (state) => state.status == MessagesStatus.ready,
    );

    bloc.add(const MessagesThreadRead('c1'));
    await bloc.stream.firstWhere(
      (state) => state.conversations.first.unreadCount == 0,
    );

    expect(bloc.state.unreadConversationCount, 1);
    expect(bloc.state.conversations.last.unreadCount, 1);
    // No second request: the badge was cleared locally.
    expect(api.customerUnreadFlags, hasLength(1));

    await bloc.close();
  });

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
}
