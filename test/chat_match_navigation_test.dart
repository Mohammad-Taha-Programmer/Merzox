import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/features/messages/bloc/chat_bloc.dart';
import 'package:merzox/features/messages/bloc/chat_event.dart';
import 'package:merzox/features/messages/bloc/chat_state.dart';
import 'package:merzox/features/messages/widgets/match_navigator.dart';
import 'package:merzox/services/api_service.dart';

import 'localization_test_harness.dart';

/// Arriving at a thread from a search result.
///
/// The place a reader chose is the FIRST time the phrase was said, and the
/// thread is served newest first - so the place they chose can be several
/// pages behind the end. Opening the thread and landing at the bottom would
/// answer a different question from the one they asked.
///
/// When it genuinely cannot be reached, the screen says so. Landing near it
/// and letting them believe they had arrived is the one outcome worse than
/// not going.

const int _pageSize = 30;

MessageApiModel _message(int index) => MessageApiModel(
  id: 'm$index',
  conversationId: 'c1',
  senderType: index.isEven ? 'customer' : 'business',
  senderName: 'ياسمين',
  body: index % 7 == 0 ? 'وين صارت الطلبية رقم $index' : 'رسالة رقم $index',
  isMine: index.isEven,
  readAt: null,
  createdAt: DateTime(2026, 9, 6, 9, 0).add(Duration(minutes: index)),
);

class _ThreadApi extends ApiService {
  /// Oldest first, as the thread reads.
  final List<MessageApiModel> all;
  final List<int> pagesAsked = <int>[];
  int readCalls = 0;

  _ThreadApi(int count) : all = List<MessageApiModel>.generate(count, _message);

  @override
  Future<ConversationMessagesApiResponse> conversationMessages({
    required String token,
    required String conversationId,
    int page = 1,
    int limit = _pageSize,
  }) async {
    pagesAsked.add(page);

    // The wire order is newest first, so a page is a window counted back from
    // the end; the response hands it on oldest first.
    final List<MessageApiModel> newestFirst = all.reversed.toList();
    final int skip = (page - 1) * limit;
    final List<MessageApiModel> window = newestFirst
        .skip(skip)
        .take(limit)
        .toList()
        .reversed
        .toList();

    return ConversationMessagesApiResponse(
      conversation: ConversationApiModel(
        id: conversationId,
        title: 'ياسمين خالد',
        avatarUrl: '',
        business: null,
        customer: null,
        lastMessage: const ConversationLastMessageApiModel(
          body: '',
          senderType: 'customer',
          sentAt: null,
        ),
        unreadCount: 0,
        messageCount: all.length,
        updatedAt: null,
      ),
      messages: window,
      page: page,
      hasMore: skip + window.length < all.length,
    );
  }

  @override
  Future<ConversationApiModel> markConversationRead({
    required String token,
    required String conversationId,
  }) async {
    readCalls += 1;
    throw StateError('not needed by these tests');
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

ChatBloc _chat(_ThreadApi api, {List<String> matchIds = const <String>[]}) =>
    ChatBloc(
      apiService: api,
      authSessionService: const _Session(),
      conversationId: 'c1',
      title: 'ياسمين خالد',
      highlightQuery: 'الطلبية',
      matchIds: matchIds,
    );

Future<void> _settle(ChatBloc bloc) async {
  for (int frame = 0; frame < 40; frame += 1) {
    await Future<void>.delayed(Duration.zero);
    if (bloc.state.status == ChatStatus.ready ||
        bloc.state.status == ChatStatus.failure) {
      // One more turn, so the anchor walk that follows the first page runs.
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  group('reaching the place that was tapped', () {
    test('a thread opened normally loads one page and stops', () async {
      final _ThreadApi api = _ThreadApi(200);
      final ChatBloc bloc = _chat(api);

      bloc.add(const ChatStarted());
      await _settle(bloc);

      expect(api.pagesAsked, <int>[1]);
      expect(bloc.state.matchIndex, -1);
      await bloc.close();
    });

    test('it pages back until the chosen message is actually loaded', () async {
      final _ThreadApi api = _ThreadApi(200);
      // m7 is near the very start of a 200-message thread: several pages back.
      final ChatBloc bloc = _chat(api, matchIds: <String>['m7', 'm70']);

      bloc.add(const ChatStarted());
      await _settle(bloc);

      expect(
        bloc.state.messages.any((MessageApiModel m) => m.id == 'm7'),
        isTrue,
      );
      expect(bloc.state.anchorReached, isTrue);
      expect(api.pagesAsked.length, greaterThan(1));
      await bloc.close();
    });

    test('it opens at the first occurrence, not the newest', () async {
      final _ThreadApi api = _ThreadApi(60);
      final ChatBloc bloc = _chat(api, matchIds: <String>['m7', 'm14', 'm21']);

      bloc.add(const ChatStarted());
      await _settle(bloc);

      expect(bloc.state.currentMatchId, 'm7');
      await bloc.close();
    });

    test('a match already on the first page costs no extra request', () async {
      final _ThreadApi api = _ThreadApi(20);
      final ChatBloc bloc = _chat(api, matchIds: <String>['m14']);

      bloc.add(const ChatStarted());
      await _settle(bloc);

      expect(api.pagesAsked, <int>[1]);
      expect(bloc.state.anchorReached, isTrue);
      await bloc.close();
    });

    test('one tap cannot become an unbounded run of requests', () async {
      // Far more history than the cap allows, with a match that is not there
      // at all - the pathological case the ceiling exists for.
      final _ThreadApi api = _ThreadApi(30 * (kChatAnchorMaxPages + 8));
      final ChatBloc bloc = _chat(api, matchIds: <String>['nowhere']);

      bloc.add(const ChatStarted());
      await _settle(bloc);

      expect(api.pagesAsked.length, lessThanOrEqualTo(kChatAnchorMaxPages + 1));
      // And it says so, rather than leaving the reader somewhere else.
      expect(bloc.state.anchorReached, isFalse);
      await bloc.close();
    });

    test('reaching the end of a short thread is not a failure', () async {
      final _ThreadApi api = _ThreadApi(10);
      final ChatBloc bloc = _chat(api, matchIds: <String>['gone']);

      bloc.add(const ChatStarted());
      await _settle(bloc);

      expect(bloc.state.status, ChatStatus.ready);
      expect(bloc.state.anchorReached, isFalse);
      await bloc.close();
    });
  });

  group('walking between occurrences', () {
    test('forward moves through the conversation as it happened', () async {
      final _ThreadApi api = _ThreadApi(40);
      final ChatBloc bloc = _chat(api, matchIds: <String>['m7', 'm14', 'm21']);

      bloc.add(const ChatStarted());
      await _settle(bloc);

      bloc.add(const ChatMatchStepped(1));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.currentMatchId, 'm14');
      await bloc.close();
    });

    test('it wraps rather than reaching a dead button', () async {
      final _ThreadApi api = _ThreadApi(40);
      final ChatBloc bloc = _chat(api, matchIds: <String>['m7', 'm14']);

      bloc.add(const ChatStarted());
      await _settle(bloc);

      // Back from the first: the last, not nowhere.
      bloc.add(const ChatMatchStepped(-1));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.currentMatchId, 'm14');

      bloc.add(const ChatMatchStepped(1));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.currentMatchId, 'm7');

      await bloc.close();
    });

    test('stepping a thread with no matches does nothing', () async {
      final _ThreadApi api = _ThreadApi(10);
      final ChatBloc bloc = _chat(api);

      bloc.add(const ChatStarted());
      await _settle(bloc);
      bloc.add(const ChatMatchStepped(1));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.matchIndex, -1);
      expect(bloc.state.currentMatchId, '');
      await bloc.close();
    });
  });

  group('the counter and its two arrows', () {
    Future<void> pumpNavigator(
      WidgetTester tester, {
      required int current,
      required int total,
      VoidCallback? onNext,
      VoidCallback? onPrevious,
    }) async {
      await pumpLocalized(
        tester,
        Scaffold(
          body: Center(
            child: MatchNavigator(
              current: current,
              total: total,
              onNext: onNext ?? () {},
              onPrevious: onPrevious ?? () {},
            ),
          ),
        ),
      );
    }

    testWidgets('it counts from one, the way a reader counts', (
      WidgetTester tester,
    ) async {
      await pumpNavigator(tester, current: 0, total: 9);

      // Standing at the first of nine, not at the zeroth.
      expect(find.text('1 من 9'), findsOneWidget);
    });

    testWidgets('both arrows are offered and reach their callbacks', (
      WidgetTester tester,
    ) async {
      int forward = 0;
      int back = 0;

      await pumpNavigator(
        tester,
        current: 1,
        total: 3,
        onNext: () => forward += 1,
        onPrevious: () => back += 1,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('merzox.chat.matchNext')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('merzox.chat.matchPrevious')),
      );
      await tester.pump();

      expect(forward, 1);
      expect(back, 1);
    });
  });
}
