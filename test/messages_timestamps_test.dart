import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/features/messages/bloc/chat_bloc.dart';
import 'package:merzox/features/messages/bloc/chat_event.dart';
import 'package:merzox/features/messages/pages/chat_page.dart';
import 'package:merzox/features/messages/pages/messages_inbox_view.dart';
import 'package:merzox/services/api_service.dart';

import 'localization_test_harness.dart';

/// The two clocks in the messages feature.
///
/// The inbox row answers "how long have they been waiting for me", which is
/// the other side's last message - not the thread's, because answering someone
/// moves the thread and would move the stamp onto your own reply.
///
/// Inside the thread every message carries its own moment, with the day, so a
/// conversation read weeks later does not say 9:43 without saying 9:43 of when.

ConversationApiModel _thread({
  DateTime? received,
  required DateTime lastMessageAt,
}) {
  return ConversationApiModel(
    id: 'c1',
    title: 'ياسمين خالد',
    avatarUrl: '',
    business: null,
    customer: null,
    lastMessage: ConversationLastMessageApiModel(
      body: 'تمام، شكرا كثير',
      senderType: 'business',
      sentAt: lastMessageAt,
    ),
    lastReceivedAt: received,
    unreadCount: 0,
    messageCount: 6,
    updatedAt: lastMessageAt,
  );
}

class _ThreadApi extends ApiService {
  final List<MessageApiModel> messages;

  _ThreadApi(this.messages);

  @override
  Future<ConversationMessagesApiResponse> conversationMessages({
    required String token,
    required String conversationId,
    int page = 1,
    int limit = 30,
  }) async => ConversationMessagesApiResponse(
    conversation: _thread(lastMessageAt: DateTime(2026, 9, 6, 9, 43)),
    messages: messages,
    page: page,
    hasMore: false,
  );

  @override
  Future<ConversationApiModel> markConversationRead({
    required String token,
    required String conversationId,
  }) async => _thread(lastMessageAt: DateTime(2026, 9, 6, 9, 43));

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

MessageApiModel _message({
  required String id,
  required String body,
  required bool isMine,
  required DateTime at,
}) => MessageApiModel(
  id: id,
  conversationId: 'c1',
  senderType: isMine ? 'customer' : 'business',
  senderName: 'ياسمين',
  body: body,
  isMine: isMine,
  readAt: null,
  createdAt: at,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  group('the stamp on an inbox row', () {
    test('it is the moment they last wrote, not the moment you replied', () {
      final DateTime theyWrote = DateTime(2026, 9, 6, 9, 40);
      final DateTime youReplied = DateTime(2026, 9, 6, 9, 43);

      // Your reply moved the thread to the top; it must not move the clock.
      expect(
        conversationStamp(
          _thread(received: theyWrote, lastMessageAt: youReplied),
        ),
        theyWrote,
      );
    });

    test('it does not go backwards when they write again', () {
      final DateTime later = DateTime(2026, 9, 6, 10, 5);

      expect(
        conversationStamp(_thread(received: later, lastMessageAt: later)),
        later,
      );
    });

    test('a thread nobody has answered yet still shows a time', () {
      final DateTime youWrote = DateTime(2026, 9, 6, 9, 43);

      // There is no received message to point at, and a hole where a time
      // belongs reads as a fault rather than as an absence.
      expect(conversationStamp(_thread(lastMessageAt: youWrote)), youWrote);
    });

    test('a server that says nothing at all does not crash the row', () {
      expect(
        conversationStamp(_thread(lastMessageAt: DateTime(2026, 9, 6))),
        isNotNull,
      );
    });

    test('the field survives the wire', () {
      final ConversationApiModel parsed = ConversationApiModel.fromJson(
        <String, dynamic>{
          'id': 'c1',
          'title': 'ياسمين',
          'lastMessage': <String, dynamic>{
            'body': 'مرحبا',
            'senderType': 'customer',
            'sentAt': '2026-09-06T09:43:00.000Z',
          },
          'lastReceivedAt': '2026-09-06T09:40:00.000Z',
        },
      );

      expect(parsed.lastReceivedAt, DateTime.utc(2026, 9, 6, 9, 40));
      expect(conversationStamp(parsed), parsed.lastReceivedAt);
    });

    test('an older server that omits it falls back rather than blanking', () {
      final ConversationApiModel parsed = ConversationApiModel.fromJson(
        <String, dynamic>{
          'id': 'c1',
          'lastMessage': <String, dynamic>{
            'sentAt': '2026-09-06T09:43:00.000Z',
          },
        },
      );

      expect(parsed.lastReceivedAt, isNull);
      expect(conversationStamp(parsed), isNotNull);
    });
  });

  group('the stamp under a message', () {
    test('it carries the day as well as the clock', () {
      final String stamp = merzoxMessageStamp(DateTime(2026, 9, 6, 9, 43));

      // A thread read weeks later said 9:43 without saying 9:43 of when.
      expect(stamp, contains('2026/09/06'));
      expect(stamp, contains('9:43'));
    });

    test('the day is written the one way the app writes days', () {
      expect(
        merzoxMessageStamp(DateTime(2026, 2, 5, 14, 7)),
        startsWith('2026/02/05'),
      );
    });

    test('midnight and noon are not both twelve of the same kind', () {
      expect(
        merzoxMessageStamp(DateTime(2026, 9, 6, 0, 5)),
        contains('12:05 AM'),
      );
      expect(
        merzoxMessageStamp(DateTime(2026, 9, 6, 12, 5)),
        contains('12:05 PM'),
      );
    });

    test('a message with no moment reads as nothing, not as a placeholder', () {
      expect(merzoxMessageStamp(null), '');
    });

    testWidgets('every message in the thread carries one', (
      WidgetTester tester,
    ) async {
      final ChatBloc bloc = ChatBloc(
        apiService: _ThreadApi(<MessageApiModel>[
          _message(
            id: 'm1',
            body: 'مرحبا ، عندي استفسار ؟',
            isMine: true,
            at: DateTime(2026, 9, 6, 9, 40),
          ),
          _message(
            id: 'm2',
            body: 'هلا ، تفضلي شو عاوزة ؟',
            isMine: false,
            at: DateTime(2026, 9, 6, 9, 43),
          ),
        ]),
        authSessionService: const _Session(),
        conversationId: 'c1',
        title: 'ياسمين خالد',
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

      // One under what you wrote and one under what you were told: the stamp
      // used to live inside the bubble, where your own was white on blue.
      expect(find.text('2026/09/06 - 9:40 AM'), findsOneWidget);
      expect(find.text('2026/09/06 - 9:43 AM'), findsOneWidget);
    });

    testWidgets('it is small, but not smaller than a person can read', (
      WidgetTester tester,
    ) async {
      final ChatBloc bloc = ChatBloc(
        apiService: _ThreadApi(<MessageApiModel>[
          _message(
            id: 'm1',
            body: 'تمام',
            isMine: false,
            at: DateTime(2026, 9, 6, 9, 43),
          ),
        ]),
        authSessionService: const _Session(),
        conversationId: 'c1',
        title: 'ياسمين خالد',
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

      final Text stamp = tester.widget<Text>(find.text('2026/09/06 - 9:43 AM'));

      expect(stamp.style!.fontSize, kChatStampSize);
      // The 9pt it used to be, inside the bubble, was past the point of being
      // readable at a glance.
      expect(kChatStampSize, greaterThan(9));
    });
  });
}
