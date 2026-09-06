import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/features/messages/bloc/messages_search_bloc.dart';
import 'package:merzox/features/messages/bloc/messages_search_event.dart';
import 'package:merzox/features/messages/bloc/messages_search_state.dart';
import 'package:merzox/features/messages/highlighted_text.dart';
import 'package:merzox/features/messages/widgets/messages_search_results.dart';
import 'package:merzox/services/api_service.dart';

import 'localization_test_harness.dart';

/// Searching the inbox.
///
/// Two questions share one box. A name should offer the thread and open it at
/// the newest message; a phrase should offer the place it was said and open it
/// there. Everything below is one of those two promises.

class _SearchApi extends ApiService {
  final List<String> asked = <String>[];
  ConversationSearchApiResponse answer;
  bool refuse = false;

  /// Held open so a test can decide when an answer lands.
  Completer<void>? gate;

  _SearchApi({ConversationSearchApiResponse? answer})
    : answer =
          answer ??
          const ConversationSearchApiResponse(
            query: '',
            people: <ConversationApiModel>[],
            messages: <ConversationMessageMatchApiModel>[],
          );

  @override
  Future<ConversationSearchApiResponse> searchConversations({
    required String token,
    required String query,
    bool businessAudience = false,
  }) async {
    asked.add(query);
    if (gate != null) await gate!.future;
    if (refuse) throw StateError('offline');
    return answer;
  }
}

class _Session implements AuthSessionService {
  const _Session();

  @override
  Future<AuthSessionSnapshot> read() async =>
      const AuthSessionSnapshot(type: AuthSessionType.customer, token: 'token');

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ConversationApiModel _thread(String id, String title, {String last = 'مرحبا'}) {
  return ConversationApiModel(
    id: id,
    title: title,
    avatarUrl: '',
    business: null,
    customer: null,
    lastMessage: ConversationLastMessageApiModel(
      body: last,
      senderType: 'customer',
      sentAt: DateTime(2026, 9, 6, 9, 43),
    ),
    unreadCount: 0,
    messageCount: 4,
    updatedAt: DateTime(2026, 9, 6, 9, 43),
  );
}

ConversationMessageMatchApiModel _match(
  String title, {
  required int count,
  List<String> ids = const <String>['m1'],
  String snippet = 'وين صارت الطلبية',
}) {
  return ConversationMessageMatchApiModel(
    conversation: _thread('c-$title', title),
    matchCount: count,
    matchIds: ids,
    snippet: snippet,
    sentAt: DateTime(2026, 9, 6, 9, 40),
  );
}

MessagesSearchBloc _bloc(_SearchApi api) =>
    MessagesSearchBloc(apiService: api, authSessionService: const _Session());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  group('what the box asks, and when', () {
    test('a typed word is one request, not one per letter', () async {
      final _SearchApi api = _SearchApi();
      final MessagesSearchBloc bloc = _bloc(api);

      for (final String typed in <String>['ط', 'طل', 'طلب', 'طلبية']) {
        bloc.add(MessagesSearchQueryChanged(typed));
      }
      await Future<void>.delayed(kMessagesSearchDebounce * 3);

      expect(api.asked, <String>['طلبية']);
      await bloc.close();
    });

    test('the field echoes every letter while the asking waits', () async {
      final _SearchApi api = _SearchApi();
      final MessagesSearchBloc bloc = _bloc(api);

      bloc.add(const MessagesSearchQueryChanged('طل'));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.query, 'طل');
      expect(api.asked, isEmpty);
      await bloc.close();
    });

    test('the keyboard search key does not wait', () async {
      final _SearchApi api = _SearchApi();
      final MessagesSearchBloc bloc = _bloc(api);

      bloc.add(const MessagesSearchSubmitted('طلبية'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(api.asked, <String>['طلبية']);
      await bloc.close();
    });

    test('clearing the box clears the results without asking again', () async {
      final _SearchApi api = _SearchApi(
        answer: ConversationSearchApiResponse(
          query: 'طلبية',
          people: <ConversationApiModel>[_thread('c1', 'ياسمين خالد')],
          messages: const <ConversationMessageMatchApiModel>[],
        ),
      );
      final MessagesSearchBloc bloc = _bloc(api);

      bloc.add(const MessagesSearchSubmitted('طلبية'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bloc.state.people, hasLength(1));

      bloc.add(const MessagesSearchQueryChanged('  '));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(bloc.state.people, isEmpty);
      expect(api.asked, <String>['طلبية']);
      await bloc.close();
    });
  });

  group('answers that arrive late', () {
    test('a slow answer does not land on top of a newer question', () async {
      final _SearchApi api = _SearchApi(
        answer: ConversationSearchApiResponse(
          query: 'قديم',
          people: <ConversationApiModel>[_thread('old', 'قديم')],
          messages: const <ConversationMessageMatchApiModel>[],
        ),
      );
      api.gate = Completer<void>();
      final MessagesSearchBloc bloc = _bloc(api);

      bloc.add(const MessagesSearchSubmitted('قديم'));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // A second question overtakes the first, which only now answers.
      api.gate = null;
      api.answer = ConversationSearchApiResponse(
        query: 'جديد',
        people: <ConversationApiModel>[_thread('new', 'جديد')],
        messages: const <ConversationMessageMatchApiModel>[],
      );
      bloc.add(const MessagesSearchSubmitted('جديد'));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(bloc.state.answeredQuery, 'جديد');
      expect(bloc.state.people.single.title, 'جديد');
      await bloc.close();
    });

    test('a refused search keeps what was already found', () async {
      final _SearchApi api = _SearchApi(
        answer: ConversationSearchApiResponse(
          query: 'طلبية',
          people: <ConversationApiModel>[_thread('c1', 'ياسمين خالد')],
          messages: const <ConversationMessageMatchApiModel>[],
        ),
      );
      final MessagesSearchBloc bloc = _bloc(api);

      bloc.add(const MessagesSearchSubmitted('طلبية'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      api.refuse = true;
      bloc.add(const MessagesSearchSubmitted('طلبيات'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // A dropped connection is not evidence that what was found has stopped
      // existing.
      expect(bloc.state.status, MessagesSearchStatus.failure);
      expect(bloc.state.people, hasLength(1));
      await bloc.close();
    });

    test('closing the box discards an answer still in the air', () async {
      final _SearchApi api = _SearchApi(
        answer: ConversationSearchApiResponse(
          query: 'طلبية',
          people: <ConversationApiModel>[_thread('c1', 'ياسمين')],
          messages: const <ConversationMessageMatchApiModel>[],
        ),
      );
      api.gate = Completer<void>();
      final MessagesSearchBloc bloc = _bloc(api);

      bloc.add(const MessagesSearchOpened());
      bloc.add(const MessagesSearchSubmitted('طلبية'));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      bloc.add(const MessagesSearchClosed());
      await Future<void>.delayed(Duration.zero);
      api.gate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(bloc.state.open, isFalse);
      expect(bloc.state.people, isEmpty);
      await bloc.close();
    });
  });

  group('what the screen says while it waits', () {
    test('"nothing found" waits for an answer about this word', () {
      const MessagesSearchState typing = MessagesSearchState(
        status: MessagesSearchStatus.searching,
        open: true,
        query: 'طلبية',
      );

      // Between a keystroke and its answer the screen must not announce a
      // result it has not been given.
      expect(typing.foundNothing, isFalse);

      const MessagesSearchState answered = MessagesSearchState(
        status: MessagesSearchStatus.ready,
        open: true,
        query: 'طلبية',
        answeredQuery: 'طلبية',
      );
      expect(answered.foundNothing, isTrue);
    });

    test('an open box with nothing typed still shows the inbox', () {
      const MessagesSearchState opened = MessagesSearchState(open: true);

      expect(opened.showsResults, isFalse);
    });
  });

  group('marking the word that was searched for', () {
    test('every occurrence is found, not just the first', () {
      expect(
        highlightRanges('الطلبية جاهزة والطلبية الثانية', 'الطلبية'),
        hasLength(2),
      );
    });

    test('overlaps are not double counted', () {
      // "aa" in "aaaa" is two, not three.
      expect(highlightRanges('aaaa', 'aa'), hasLength(2));
    });

    test('case is ignored, and the original letters are kept', () {
      final List<({int end, int start})> found = highlightRanges(
        'Order shipped',
        'ORDER',
      );

      expect(found.single.start, 0);
      expect(found.single.end, 5);
    });

    test('an empty query marks nothing rather than everything', () {
      expect(highlightRanges('الطلبية', '   '), isEmpty);
    });

    test('the marked run carries the wash and keeps the rest plain', () {
      final TextSpan span = highlightedSpan(
        text: 'وين الطلبية',
        query: 'الطلبية',
        style: const TextStyle(fontSize: 12, color: Color(0xFF3B3B3B)),
        background: const Color(0xFFDEEEF8),
      );

      final List<InlineSpan> parts = span.children!;
      expect((parts.first as TextSpan).text, 'وين ');
      expect((parts.first as TextSpan).style!.backgroundColor, isNull);
      expect((parts.last as TextSpan).text, 'الطلبية');
      expect(
        (parts.last as TextSpan).style!.backgroundColor,
        const Color(0xFFDEEEF8),
      );
    });
  });

  group('the two shapes a result comes in', () {
    Future<void> pumpResults(
      WidgetTester tester,
      MessagesSearchState state, {
      void Function(ConversationApiModel)? onThread,
      void Function(ConversationMessageMatchApiModel)? onMatch,
    }) async {
      await pumpLocalized(
        tester,
        Scaffold(
          body: MessagesSearchResults(
            state: state,
            onOpenThread: onThread ?? (_) {},
            onOpenMatch: onMatch ?? (_) {},
          ),
        ),
      );
    }

    testWidgets('a name match and a phrase match sit under their own heads', (
      WidgetTester tester,
    ) async {
      await pumpResults(
        tester,
        MessagesSearchState(
          status: MessagesSearchStatus.ready,
          open: true,
          query: 'ياسمين',
          answeredQuery: 'ياسمين',
          people: <ConversationApiModel>[_thread('c1', 'ياسمين خالد')],
          messages: <ConversationMessageMatchApiModel>[
            _match('حمود حسين', count: 1),
          ],
        ),
      );

      expect(find.text('المحادثات'), findsOneWidget);
      expect(find.text('في نصوص الرسائل'), findsOneWidget);
    });

    testWidgets('tapping a name opens the thread, not a place inside it', (
      WidgetTester tester,
    ) async {
      ConversationApiModel? opened;

      await pumpResults(
        tester,
        MessagesSearchState(
          status: MessagesSearchStatus.ready,
          open: true,
          query: 'ياسمين',
          answeredQuery: 'ياسمين',
          people: <ConversationApiModel>[_thread('c1', 'ياسمين خالد')],
        ),
        onThread: (ConversationApiModel c) => opened = c,
      );

      await tester.tap(find.text('ياسمين خالد'));
      await tester.pump();

      expect(opened?.id, 'c1');
    });

    testWidgets('tapping a phrase hands back the places to stand', (
      WidgetTester tester,
    ) async {
      ConversationMessageMatchApiModel? opened;

      await pumpResults(
        tester,
        MessagesSearchState(
          status: MessagesSearchStatus.ready,
          open: true,
          query: 'الطلبية',
          answeredQuery: 'الطلبية',
          messages: <ConversationMessageMatchApiModel>[
            _match('ياسمين خالد', count: 3, ids: <String>['m1', 'm2', 'm3']),
          ],
        ),
        onMatch: (ConversationMessageMatchApiModel m) => opened = m,
      );

      await tester.tap(find.text('ياسمين خالد'));
      await tester.pump();

      expect(opened?.matchIds, <String>['m1', 'm2', 'm3']);
      // Where it opens: the first time it was said.
      expect(opened?.firstMatchId, 'm1');
    });

    testWidgets('a phrase said more than once says so before it is tapped', (
      WidgetTester tester,
    ) async {
      await pumpResults(
        tester,
        MessagesSearchState(
          status: MessagesSearchStatus.ready,
          open: true,
          query: 'الطلبية',
          answeredQuery: 'الطلبية',
          messages: <ConversationMessageMatchApiModel>[
            _match('ياسمين', count: 9, ids: <String>['m1', 'm2']),
            _match('حمود', count: 1),
          ],
        ),
      );

      // One badge, on the row that has more than one place to go.
      expect(
        find.byKey(const ValueKey<String>('merzox.messages.matchCount')),
        findsOneWidget,
      );
      expect(find.text('9'), findsOneWidget);
    });

    testWidgets('nothing found names the word that found nothing', (
      WidgetTester tester,
    ) async {
      await pumpResults(
        tester,
        const MessagesSearchState(
          status: MessagesSearchStatus.ready,
          open: true,
          query: 'خزعبلات',
          answeredQuery: 'خزعبلات',
        ),
      );

      expect(find.textContaining('خزعبلات'), findsOneWidget);
    });
  });
}
