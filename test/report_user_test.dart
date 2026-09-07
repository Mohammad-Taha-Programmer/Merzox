import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/features/messages/bloc/chat_bloc.dart';
import 'package:merzox/features/messages/bloc/chat_event.dart';
import 'package:merzox/features/messages/pages/chat_page.dart';
import 'package:merzox/services/api_service.dart';

import 'localization_test_harness.dart';

/// Telling the operator about somebody.
///
/// Whom it names is never sent - the server reads it from the conversation,
/// as it does for a block. What travels is why, and that is the part worth
/// holding to: a reason this app offers but the server refuses would be a
/// form that fails on send.

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

class _ChatApi extends ApiService {
  final List<(String conversationId, String reason, String note)> reports =
      <(String, String, String)>[];

  Object? failure;

  @override
  Future<ConversationMessagesApiResponse> conversationMessages({
    required String token,
    required String conversationId,
    int page = 1,
    int limit = 30,
  }) async => ConversationMessagesApiResponse(
    conversation: _thread(),
    messages: <MessageApiModel>[
      MessageApiModel(
        id: 'm1',
        conversationId: 'c1',
        senderType: 'business',
        senderName: 'البتول كوزماتيكس',
        body: 'مرحبا',
        isMine: false,
        readAt: null,
        createdAt: DateTime(2026, 9, 6, 9, 40),
      ),
    ],
    page: page,
    hasMore: false,
  );

  @override
  Future<ConversationApiModel> markConversationRead({
    required String token,
    required String conversationId,
  }) async => _thread();

  @override
  Future<void> reportConversationCounterpart({
    required String token,
    required String conversationId,
    required String reason,
    String note = '',
  }) async {
    if (failure != null) throw failure!;
    reports.add((conversationId, reason, note));
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

Future<void> _openReportSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('chat.threadMenu')));
  await settleFrames(tester);
  await tester.tap(find.byKey(const ValueKey<String>('chat.report')));
  await settleFrames(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  group('the reasons offered', () {
    test('are the ones the server knows, in the same words', () {
      // The app and the API live in one repository, so this is checkable
      // rather than a convention nobody enforces. A reason offered here and
      // refused there would be a form that fails on send.
      final String policy = File(
        'backend/src/policies/user-report.policy.js',
      ).readAsStringSync();

      final RegExpMatch? listed = RegExp(
        r'USER_REPORT_REASONS = Object\.freeze\(\[(.*?)\]\)',
        dotAll: true,
      ).firstMatch(policy);

      expect(listed, isNotNull);

      final List<String> serverReasons = RegExp("'([^']+)'")
          .allMatches(listed!.group(1)!)
          .map((RegExpMatch match) => match.group(1)!)
          .toList();

      expect(merzoxReportReasons, serverReasons);
    });

    test('each one has words in both languages', () async {
      for (final String language in <String>['ar', 'en']) {
        final Map<String, dynamic> catalogue =
            jsonDecode(
                  File(
                    'assets/translations/$language.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>;

        final Map<String, dynamic> reasons =
            (catalogue['messages'] as Map<String, dynamic>)['reportReasons']
                as Map<String, dynamic>;

        for (final String reason in merzoxReportReasons) {
          expect(
            reasons[reason],
            isA<String>().having((String it) => it.trim(), 'text', isNotEmpty),
            reason: '$reason has no $language wording',
          );
        }
      }
    });

    test('and the note is capped where the server caps it', () {
      final String policy = File(
        'backend/src/policies/user-report.policy.js',
      ).readAsStringSync();

      expect(policy, contains('REPORT_NOTE_MAX = $kReportNoteMax'));
    });
  });

  group('sending one', () {
    testWidgets('nothing is sent until a reason is chosen', (
      WidgetTester tester,
    ) async {
      final _ChatApi api = _ChatApi();
      await _openChat(tester, api);
      await _openReportSheet(tester);

      // A reason picked by default is a reason nobody chose, and a button
      // that looked ready would only fail at the server.
      final FilledButton send = tester.widget<FilledButton>(
        find.byKey(const ValueKey<String>('chat.reportSend')),
      );
      expect(send.onPressed, isNull);
      expect(api.reports, isEmpty);
    });

    testWidgets('a reason and the words beside it travel together', (
      WidgetTester tester,
    ) async {
      final _ChatApi api = _ChatApi();
      await _openChat(tester, api);
      await _openReportSheet(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('chat.reportReason.harassment')),
      );
      await settleFrames(tester);

      await tester.enterText(
        find.byKey(const ValueKey<String>('chat.reportNote')),
        'رسائل مسيئة',
      );
      await tester.tap(find.byKey(const ValueKey<String>('chat.reportSend')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await settleFrames(tester);

      // The conversation is the only thing named. Who is on its other side is
      // the server's to read.
      expect(api.reports, <(String, String, String)>[
        ('c1', 'harassment', 'رسائل مسيئة'),
      ]);
    });

    testWidgets('and the reader is told it landed', (
      WidgetTester tester,
    ) async {
      final _ChatApi api = _ChatApi();
      await _openChat(tester, api);
      await _openReportSheet(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('chat.reportReason.spam')),
      );
      await settleFrames(tester);
      await tester.tap(find.byKey(const ValueKey<String>('chat.reportSend')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await settleFrames(tester);

      expect(find.text('تم استلام بلاغك'), findsOneWidget);
    });

    testWidgets('a report that did not land does not say it did', (
      WidgetTester tester,
    ) async {
      final _ChatApi api = _ChatApi()..failure = StateError('server refused');
      final ChatBloc bloc = await _openChat(tester, api);

      bloc.add(const ChatReportSubmitted(reason: 'spam'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await settleFrames(tester);

      expect(bloc.state.noticeCode, isEmpty);
      expect(bloc.state.errorMessage, isNotEmpty);
    });
  });
}
