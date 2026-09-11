import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/features/messages/bloc/chat_bloc.dart';
import 'package:merzox/features/messages/bloc/chat_event.dart';
import 'package:merzox/features/messages/pages/bookmarks_page.dart';
import 'package:merzox/features/messages/pages/chat_page.dart';
import 'package:merzox/services/api_service.dart';

import 'localization_test_harness.dart';

/// The three things a long press offers: answer this one, copy it, mark it.
///
/// Copying is the reader's own clipboard and never reaches the server. The
/// other two do, and both name a message by id - the server looks each one up
/// inside the thread the caller is already in, which is tested there. What is
/// tested here is that the app asks for exactly that and nothing more.

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

MessageApiModel _message({
  String id = 'm1',
  String body = 'عندي استفسار',
  bool isMine = false,
  bool bookmarked = false,
  MessageReplyApiModel? replyTo,
  SharedProductApiModel? shared,
}) => MessageApiModel(
  id: id,
  conversationId: 'c1',
  senderType: isMine ? 'customer' : 'business',
  senderName: 'ياسمين',
  body: body,
  sharedProduct: shared,
  replyTo: replyTo,
  bookmarked: bookmarked,
  isMine: isMine,
  readAt: null,
  createdAt: DateTime(2026, 9, 6, 9, 40),
);

class _ChatApi extends ApiService {
  final List<MessageApiModel> messages;

  final List<String?> sentReplyIds = <String?>[];
  final List<String> sentBodies = <String>[];
  final List<(String messageId, bool bookmarked)> marks = <(String, bool)>[];

  _ChatApi({this.messages = const <MessageApiModel>[]});

  @override
  Future<ConversationMessagesApiResponse> conversationMessages({
    required String token,
    required String conversationId,
    int page = 1,
    int limit = 30,
  }) async => ConversationMessagesApiResponse(
    conversation: _thread(),
    messages: messages,
    page: page,
    hasMore: false,
  );

  @override
  Future<ConversationApiModel> markConversationRead({
    required String token,
    required String conversationId,
  }) async => _thread();

  @override
  Future<MessageApiModel> sendMessage({
    required String token,
    required String conversationId,
    required String body,
    String? productId,
    String? replyToId,
  }) async {
    sentBodies.add(body);
    sentReplyIds.add(replyToId);
    return _message(id: 'sent', body: body, isMine: true);
  }

  @override
  Future<bool> setMessageBookmark({
    required String token,
    required String conversationId,
    required String messageId,
    required bool bookmarked,
  }) async {
    marks.add((messageId, bookmarked));
    return bookmarked;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BookmarkApi extends ApiService {
  final List<BookmarkApiModel> rows;

  /// What was asked to be unmarked, and from which thread.
  final List<(String conversationId, String messageId, bool bookmarked)> marks =
      <(String, String, bool)>[];

  _BookmarkApi(this.rows);

  @override
  Future<BookmarkListApiResponse> bookmarks({
    required String token,
    int page = 1,
    int limit = 20,
  }) async =>
      BookmarkListApiResponse(bookmarks: rows, page: page, hasMore: false);

  @override
  Future<bool> setMessageBookmark({
    required String token,
    required String conversationId,
    required String messageId,
    required bool bookmarked,
  }) async {
    marks.add((conversationId, messageId, bookmarked));
    return bookmarked;
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

Future<void> _longPressFirstMessage(WidgetTester tester, String body) async {
  await tester.longPress(find.text(body));
  await settleFrames(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  group('what a long press offers', () {
    testWidgets('three things, and the mark reads as the reader left it', (
      WidgetTester tester,
    ) async {
      await _openChat(
        tester,
        _ChatApi(messages: <MessageApiModel>[_message()]),
      );

      await _longPressFirstMessage(tester, 'عندي استفسار');

      expect(
        find.byKey(const ValueKey<String>('chat.actionReply')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('chat.actionCopy')),
        findsOneWidget,
      );
      expect(find.text('وضع علامة'), findsOneWidget);
    });

    testWidgets('a marked message offers to unmark instead', (
      WidgetTester tester,
    ) async {
      await _openChat(
        tester,
        _ChatApi(messages: <MessageApiModel>[_message(bookmarked: true)]),
      );

      await _longPressFirstMessage(tester, 'عندي استفسار');

      expect(find.text('إزالة العلامة'), findsOneWidget);
      expect(find.text('وضع علامة'), findsNothing);
    });
  });

  group('answering one message', () {
    testWidgets('the quote waits over the box, and can be taken back', (
      WidgetTester tester,
    ) async {
      await _openChat(
        tester,
        _ChatApi(messages: <MessageApiModel>[_message()]),
      );

      await _longPressFirstMessage(tester, 'عندي استفسار');
      await tester.tap(find.byKey(const ValueKey<String>('chat.actionReply')));
      await settleFrames(tester);

      expect(
        find.byKey(const ValueKey<String>('chat.pendingReply')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('chat.dropPendingReply')),
      );
      await settleFrames(tester);

      expect(
        find.byKey(const ValueKey<String>('chat.pendingReply')),
        findsNothing,
      );
    });

    testWidgets('sending carries the answered message, and only its id', (
      WidgetTester tester,
    ) async {
      final _ChatApi api = _ChatApi(messages: <MessageApiModel>[_message()]);
      await _openChat(tester, api);

      await _longPressFirstMessage(tester, 'عندي استفسار');
      await tester.tap(find.byKey(const ValueKey<String>('chat.actionReply')));
      await settleFrames(tester);

      await tester.enterText(find.byType(TextField), 'تفضلي');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await settleFrames(tester);

      expect(api.sentBodies, <String>['تفضلي']);
      // The quote itself is the server's to copy from the message it names.
      expect(api.sentReplyIds, <String?>['m1']);

      // And the box is clear for the next message.
      expect(
        find.byKey(const ValueKey<String>('chat.pendingReply')),
        findsNothing,
      );
    });

    testWidgets('an answer is drawn under what it answers', (
      WidgetTester tester,
    ) async {
      await _openChat(
        tester,
        _ChatApi(
          messages: <MessageApiModel>[
            _message(),
            _message(
              id: 'm2',
              body: 'تفضلي',
              isMine: true,
              replyTo: const MessageReplyApiModel(
                messageId: 'm1',
                senderName: 'ياسمين',
                body: 'عندي استفسار',
                hasProduct: false,
                isMine: false,
              ),
            ),
          ],
        ),
      );

      expect(
        find.byKey(const ValueKey<String>('chat.quotedMessage')),
        findsOneWidget,
      );
      // The quote repeats the answered words inside the answer, so the two
      // read together however far apart they were said.
      expect(find.text('عندي استفسار'), findsNWidgets(2));
      expect(find.text('تفضلي'), findsOneWidget);
    });

    testWidgets('a quote of a shared card says what it was', (
      WidgetTester tester,
    ) async {
      // A card is a message without words, and a quote showing an empty line
      // would read as a fault.
      expect(
        quotedMessagePreview(
          const MessageReplyApiModel(
            messageId: 'm1',
            senderName: 'ياسمين',
            body: '',
            hasProduct: true,
            isMine: false,
          ),
        ),
        'بطاقة منتج',
      );
    });
  });

  group('copying and marking', () {
    testWidgets('copying puts the words on the clipboard', (
      WidgetTester tester,
    ) async {
      final List<MethodCall> clipboard = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') clipboard.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await _openChat(
        tester,
        _ChatApi(messages: <MessageApiModel>[_message()]),
      );

      await _longPressFirstMessage(tester, 'عندي استفسار');
      await tester.tap(find.byKey(const ValueKey<String>('chat.actionCopy')));
      await settleFrames(tester);

      expect(clipboard, hasLength(1));
      expect(
        (clipboard.single.arguments as Map<Object?, Object?>)['text'],
        'عندي استفسار',
      );
    });

    testWidgets('marking asks the server, and keeps what it answered', (
      WidgetTester tester,
    ) async {
      final _ChatApi api = _ChatApi(messages: <MessageApiModel>[_message()]);
      final ChatBloc bloc = await _openChat(tester, api);

      await _longPressFirstMessage(tester, 'عندي استفسار');
      await tester.tap(
        find.byKey(const ValueKey<String>('chat.actionBookmark')),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await settleFrames(tester);

      expect(api.marks, <(String, bool)>[('m1', true)]);
      expect(bloc.state.messages.single.bookmarked, isTrue);
    });
  });

  group('the marked list', () {
    testWidgets('says so plainly when there is nothing in it', (
      WidgetTester tester,
    ) async {
      await pumpLocalized(
        tester,
        BookmarksPage(
          apiService: _BookmarkApi(const <BookmarkApiModel>[]),
          authSessionService: const _Session(),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await settleFrames(tester);

      expect(find.text('لم تضع علامة على أي رسالة بعد.'), findsOneWidget);
    });

    testWidgets('shows each message under the thread it was said in', (
      WidgetTester tester,
    ) async {
      await pumpLocalized(
        tester,
        BookmarksPage(
          apiService: _BookmarkApi(<BookmarkApiModel>[
            BookmarkApiModel(
              message: _message(bookmarked: true),
              conversation: _thread(),
              markedAt: DateTime(2026, 9, 6, 10),
            ),
          ]),
          authSessionService: const _Session(),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await settleFrames(tester);

      expect(find.text('البتول كوزماتيكس'), findsOneWidget);
      expect(find.text('عندي استفسار'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('bookmark.m1')), findsOneWidget);
    });

    testWidgets('the bin takes a mark off, and the row goes with it', (
      WidgetTester tester,
    ) async {
      final _BookmarkApi api = _BookmarkApi(<BookmarkApiModel>[
        BookmarkApiModel(
          message: _message(bookmarked: true),
          conversation: _thread(),
          markedAt: DateTime(2026, 9, 6, 10),
        ),
      ]);

      await pumpLocalized(
        tester,
        BookmarksPage(apiService: api, authSessionService: const _Session()),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await settleFrames(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('bookmark.remove.m1')),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await settleFrames(tester);

      // Named by thread and message, which is how the server scopes it.
      expect(api.marks, <(String, String, bool)>[('c1', 'm1', false)]);

      // And the list is what is left, without a reload.
      expect(find.byKey(const ValueKey<String>('bookmark.m1')), findsNothing);
      expect(find.text('لم تضع علامة على أي رسالة بعد.'), findsOneWidget);
    });

    testWidgets('the way back is the board chevron, not Material arrow', (
      WidgetTester tester,
    ) async {
      await pumpLocalized(
        tester,
        BookmarksPage(
          apiService: _BookmarkApi(const <BookmarkApiModel>[]),
          authSessionService: const _Session(),
        ),
      );
      await settleFrames(tester);

      final Icon icon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey<String>('bookmarks.back')),
          matching: find.byType(Icon),
        ),
      );

      // Named for what it does; Material turns it for the reading, which is
      // the mistake this app has made three times by choosing a direction.
      expect(icon.icon, Icons.chevron_left_rounded);
      expect(icon.icon!.matchTextDirection, isTrue);
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    });
  });
}
