import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/features/messages/bloc/chat_bloc.dart';
import 'package:merzox/features/messages/bloc/chat_event.dart';
import 'package:merzox/features/messages/pages/blocked_users_page.dart';
import 'package:merzox/features/messages/pages/chat_page.dart';
import 'package:merzox/features/notifications/widgets/global_notification_bell.dart';
import 'package:merzox/services/api_service.dart';

import 'localization_test_harness.dart';

/// Refusing to hear from someone.
///
/// Whom a block names is never sent: it is the other side of the conversation
/// it is made from, which the server reads from the conversation itself. What
/// is tested here is that the app asks for exactly that, and that a closed
/// thread stops offering a way to write in it.

ConversationApiModel _thread() => ConversationApiModel(
  id: 'c1',
  title: 'البتول كوزماتيكس',
  avatarUrl: '',
  business: null,
  customer: null,
  lastMessage: ConversationLastMessageApiModel(
    body: 'مرحبا',
    senderType: 'customer',
    sentAt: DateTime(2026, 9, 6, 9, 40),
  ),
  lastReceivedAt: DateTime(2026, 9, 6, 9, 40),
  unreadCount: 0,
  messageCount: 1,
  updatedAt: DateTime(2026, 9, 6, 9, 40),
);

MessageApiModel _message() => MessageApiModel(
  id: 'm1',
  conversationId: 'c1',
  senderType: 'business',
  senderName: 'البتول كوزماتيكس',
  body: 'مرحبا',
  isMine: false,
  readAt: null,
  createdAt: DateTime(2026, 9, 6, 9, 40),
);

class _ChatApi extends ApiService {
  final bool blockedByMe;
  final bool blockedMe;

  final List<(String conversationId, bool blocked)> asked =
      <(String, bool)>[];
  final List<String> sent = <String>[];

  _ChatApi({this.blockedByMe = false, this.blockedMe = false});

  @override
  Future<ConversationMessagesApiResponse> conversationMessages({
    required String token,
    required String conversationId,
    int page = 1,
    int limit = 30,
  }) async => ConversationMessagesApiResponse(
    conversation: _thread(),
    messages: <MessageApiModel>[_message()],
    page: page,
    hasMore: false,
    blockedByMe: blockedByMe,
    blockedMe: blockedMe,
  );

  @override
  Future<ConversationApiModel> markConversationRead({
    required String token,
    required String conversationId,
  }) async => _thread();

  @override
  Future<bool> setConversationBlock({
    required String token,
    required String conversationId,
    required bool blocked,
  }) async {
    asked.add((conversationId, blocked));
    return blocked;
  }

  @override
  Future<MessageApiModel> sendMessage({
    required String token,
    required String conversationId,
    required String body,
    String? productId,
    String? replyToId,
  }) async {
    sent.add(body);
    return _message();
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BlockListApi extends ApiService {
  final List<BlockedUserApiModel> rows;
  final List<String> unblocked = <String>[];

  _BlockListApi(this.rows);

  @override
  Future<BlockedUserListApiResponse> blockedUsers({
    required String token,
    int page = 1,
    int limit = 20,
  }) async =>
      BlockedUserListApiResponse(blocks: rows, page: page, hasMore: false);

  @override
  Future<void> unblockUser({
    required String token,
    required String userId,
  }) async {
    unblocked.add(userId);
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Session implements AuthSessionService {
  const _Session();

  @override
  Future<AuthSessionSnapshot> read() async =>
      const AuthSessionSnapshot(type: AuthSessionType.customer, token: 'token');

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ChatBloc> _openChat(WidgetTester tester, _ChatApi api) async {
  final ChatBloc bloc = ChatBloc(
    apiService: api,
    authSessionService: const _Session(),
    conversationId: 'c1',
    title: 'البتول كوزماتيكس',
  );
  addTearDown(bloc.close);

  bloc.add(const ChatStarted());
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );

  await pumpLocalized(
    tester,
    BlocProvider<ChatBloc>.value(value: bloc, child: const ChatPage()),
  );

  return bloc;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  group('where the menu is', () {
    testWidgets('it stands clear of the bell that floats over that corner', (
      WidgetTester tester,
    ) async {
      // The bell is drawn above the router, so anything left in this corner
      // is not merely half covered but unclickable: its taps go to the bell.
      // The menu was there, and the block button could not be reached at all.
      await _openChat(tester, _ChatApi());

      final Rect menu = tester.getRect(
        find.byKey(const ValueKey<String>('chat.threadMenu')),
      );

      expect(
        menu.left,
        greaterThanOrEqualTo(kGlobalBellInset + kGlobalBellReservedWidth),
      );
    });
  });

  group('closing a conversation', () {
    testWidgets('the thread menu offers it, and names nobody', (
      WidgetTester tester,
    ) async {
      final _ChatApi api = _ChatApi();
      await _openChat(tester, api);

      await tester.tap(find.byKey(const ValueKey<String>('chat.threadMenu')));
      await settleFrames(tester);

      expect(find.text('حظر هذا المستخدم'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('chat.toggleBlock')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await settleFrames(tester);

      // The conversation is the only thing named. Who is on its other side is
      // the server's to read, so there is no id here to get wrong.
      expect(api.asked, <(String, bool)>[('c1', true)]);
    });

    testWidgets('a thread this reader closed offers to open it again', (
      WidgetTester tester,
    ) async {
      final _ChatApi api = _ChatApi(blockedByMe: true);
      await _openChat(tester, api);

      await tester.tap(find.byKey(const ValueKey<String>('chat.threadMenu')));
      await settleFrames(tester);

      // The notice over the closed box offers it too, so this asks the menu
      // tile itself rather than counting the words on the screen.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('chat.toggleBlock')),
          matching: find.text('إلغاء الحظر'),
        ),
        findsOneWidget,
      );
      expect(find.text('حظر هذا المستخدم'), findsNothing);
    });
  });

  group('what a closed thread looks like', () {
    testWidgets('the message box is replaced by why it is gone', (
      WidgetTester tester,
    ) async {
      // A box that took words nothing would carry is worse than its absence.
      await _openChat(tester, _ChatApi(blockedByMe: true));

      expect(find.byType(TextField), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('chat.blockedNotice')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('chat.unblockFromNotice')),
        findsOneWidget,
      );
    });

    testWidgets('a door closed by the other side is not this reader to open', (
      WidgetTester tester,
    ) async {
      await _openChat(tester, _ChatApi(blockedMe: true));

      expect(find.byType(TextField), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('chat.blockedNotice')),
        findsOneWidget,
      );
      // No way out offered, because there is none: the block is not theirs.
      expect(
        find.byKey(const ValueKey<String>('chat.unblockFromNotice')),
        findsNothing,
      );
      expect(find.text('هذه المحادثة مغلقة، ولا يمكن الإرسال فيها.'), findsOneWidget);
    });

    testWidgets('and nothing is sent across it', (WidgetTester tester) async {
      final _ChatApi api = _ChatApi(blockedByMe: true);
      final ChatBloc bloc = await _openChat(tester, api);

      // The server refuses it too; stopping here means the app never sends
      // what it already knows will come back refused.
      bloc.add(const ChatMessageSent('مرحبا'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );

      expect(api.sent, isEmpty);
    });
  });

  group('the list of closed doors', () {
    testWidgets('says so plainly when there is nothing in it', (
      WidgetTester tester,
    ) async {
      await pumpLocalized(
        tester,
        BlockedUsersPage(
          apiService: _BlockListApi(const <BlockedUserApiModel>[]),
          authSessionService: const _Session(),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await settleFrames(tester);

      expect(find.text('لم تحظر أحداً.'), findsOneWidget);
    });

    testWidgets('opening one again takes it off the list', (
      WidgetTester tester,
    ) async {
      final _BlockListApi api = _BlockListApi(<BlockedUserApiModel>[
        BlockedUserApiModel(
          userId: 'u2',
          name: 'البتول كوزماتيكس',
          avatarUrl: '',
          blockedAt: DateTime(2026, 9, 6, 10),
        ),
      ]);

      await pumpLocalized(
        tester,
        BlockedUsersPage(
          apiService: api,
          authSessionService: const _Session(),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await settleFrames(tester);

      expect(find.text('البتول كوزماتيكس'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('blockedUser.unblock.u2')),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await settleFrames(tester);

      expect(api.unblocked, <String>['u2']);
      expect(
        find.byKey(const ValueKey<String>('blockedUser.u2')),
        findsNothing,
      );
      expect(find.text('لم تحظر أحداً.'), findsOneWidget);
    });
  });
}
