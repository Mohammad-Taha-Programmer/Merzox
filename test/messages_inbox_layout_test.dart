import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/features/messages/bloc/messages_bloc.dart';
import 'package:merzox/features/messages/bloc/messages_event.dart';
import 'package:merzox/features/messages/bloc/messages_search_bloc.dart';
import 'package:merzox/features/messages/pages/messages_inbox_view.dart';
import 'package:merzox/core/widgets/merzox_back_chevron.dart';
import 'package:merzox/services/api_service.dart';

import 'golden/merzox_golden_harness.dart';

/// How the inbox is laid out.
///
/// On the golden harness rather than as a bare widget test: without the
/// bundled fonts Arabic renders in a wide fallback face, and every horizontal
/// measurement below would be about that face instead of about the layout.

const double _gutter = 16;

/// Long enough to run onto a second line at the row's width, which is what
/// makes the stamp's alignment observable at all.
const String _preview =
    'قديه بدها الطلبية لتوصلني؟ وهل يوجد توصيل مجاني '
    'للطلبات فوق مئة شيقل داخل المدينة؟';

class _InboxApi extends ApiService {
  @override
  Future<ConversationListApiResponse> conversations({
    required String token,
    bool unreadOnly = false,
    int page = 1,
    int limit = 20,
  }) async {
    return ConversationListApiResponse(
      conversations: <ConversationApiModel>[
        ConversationApiModel(
          id: 'c1',
          title: 'ياسمين خالد',
          avatarUrl: '',
          business: null,
          customer: null,
          lastMessage: ConversationLastMessageApiModel(
            body: _preview,
            senderType: 'customer',
            sentAt: DateTime.now(),
          ),
          unreadCount: 1,
          messageCount: 4,
          updatedAt: DateTime.now(),
        ),
      ],
      unreadConversationCount: 1,
      page: 1,
      hasMore: false,
    );
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

Future<void> _pumpInbox(WidgetTester tester, {bool showBack = false}) async {
  final MessagesBloc bloc = MessagesBloc(
    apiService: _InboxApi(),
    authSessionService: const _Session(),
  );

  await tester.runAsync(() async {
    bloc.add(const MessagesStarted());
    await Future<void>.delayed(const Duration(milliseconds: 30));
  });

  await pumpMerzoxGoldenPage(
    tester,
    MultiBlocProvider(
      providers: [
        BlocProvider<MessagesBloc>.value(value: bloc),
        BlocProvider<MessagesSearchBloc>(
          create: (_) => MessagesSearchBloc(
            apiService: _InboxApi(),
            authSessionService: const _Session(),
          ),
        ),
      ],
      child: withMerzoxGoldenDeviceInsets(
        Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: Builder(
              builder: (BuildContext context) => MessagesInboxView(
                title: 'messages.title'.tr(),
                showBack: showBack,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  addTearDown(bloc.close);
}

double _fontSize(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!.fontSize!;

/// Taps, and lets the bloc actually answer.
///
/// The golden harness pumps inside `runAsync`, so every stream the tree
/// subscribed to lives on the real event loop. A tap followed by `pump` alone
/// advances the faked clock the bloc's answer is not on, and the screen looks
/// as though nothing happened - which is a property of the harness, not of the
/// widget.
Future<void> _tapAndSettle(WidgetTester tester, Key key) async {
  await tester.runAsync(() async {
    await tester.tap(find.byKey(key));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump();
  });
  await settleMerzoxGoldenFrames(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadMerzoxGoldenFonts();
    await loadMerzoxGoldenDateSymbols();
  });

  group('the two filters', () {
    testWidgets('the whole width sits between them, not a fixed gap', (
      WidgetTester tester,
    ) async {
      await _pumpInbox(tester);

      // The whole tab, not just its word: the unread one carries its count on
      // the far side of the label, and that is part of what is being pushed to
      // the edge.
      final Rect all = tester.getRect(
        find.ancestor(of: find.text('الكل'), matching: find.byType(InkWell)),
      );
      final Rect unread = tester.getRect(
        find.ancestor(
          of: find.text('غير مقروءة'),
          matching: find.byType(InkWell),
        ),
      );

      // The three dots now hold the reading edge, with `الكل` immediately
      // inside them - the reader asked for them before it - so the tab is no
      // longer the outermost thing on that side.
      final Rect menu = tester.getRect(
        find.byKey(const ValueKey<String>('messages.inboxMenu')),
      );

      expect(menu.right, closeTo(merzoxGoldenSurfaceSize.width - _gutter, 6));

      // And they stand together: a thumb's width apart, not half the screen.
      // Three children of a space-between row split the leftover width into
      // two gaps, which put as much space here as between the two filters.
      expect(menu.left - all.right, closeTo(kInboxMenuGap, 2));

      // The far edge is unchanged, and the space between the two tabs is
      // still the width rather than a constant. A fixed gap would leave both
      // of them huddled at the reading edge, which is what the screen did
      // before.
      expect(unread.left, closeTo(_gutter, 6));
      // Eighty-odd rather than the hundred-odd it was: the three dots take
      // their width out of the middle. What is asserted is that the gap is
      // the leftover width, which is why it moved when something joined the
      // row - a fixed gap would not have.
      expect(all.left - unread.right, greaterThan(60));

      // The three of them together span the content box: whatever is left
      // over after the dots and the two labels is the gap, which is the
      // property a fixed gap would not have.
      expect(
        menu.right - unread.left,
        closeTo(merzoxGoldenSurfaceSize.width - _gutter * 2, 12),
      );
    });

    testWidgets('`الكل` is the one at the reading edge', (
      WidgetTester tester,
    ) async {
      await _pumpInbox(tester);

      // Right of `غير مقروءة` in Arabic: the artboard's order, and the
      // opposite of what spaceBetween alone would have produced.
      expect(
        tester.getCenter(find.text('الكل')).dx,
        greaterThan(tester.getCenter(find.text('غير مقروءة')).dx),
      );
    });
  }, skip: merzoxGoldenPlatformSkip);

  group('a row', () {
    testWidgets('the stamp sits on the name, not halfway down the row', (
      WidgetTester tester,
    ) async {
      await _pumpInbox(tester);

      final Rect name = tester.getRect(find.text('ياسمين خالد'));
      final Rect stamp = tester.getRect(
        find.textContaining(RegExp(r'^\d{1,2}:\d{2}$')),
      );

      // The row's last message runs to a second line, which is where the two
      // arrangements part company: a stamp centred against a tall name column
      // drifts down past the name entirely, while the artboard keeps it on the
      // name's line however long the message is.
      expect(find.text(_preview), findsOneWidget);
      expect(stamp.top - name.top, closeTo(0, 4));
    });

    testWidgets('the row reads at a comfortable size, not the board size', (
      WidgetTester tester,
    ) async {
      await _pumpInbox(tester);

      // The artboard's 13 and 10 measured fine at desk distance and read
      // small on a phone.
      expect(_fontSize(tester, 'ياسمين خالد'), kInboxNameSize);
      expect(_fontSize(tester, _preview), kInboxPreviewSize);
      expect(kInboxNameSize, greaterThan(13));
      expect(kInboxPreviewSize, greaterThan(10));
    });
  }, skip: merzoxGoldenPlatformSkip);

  group('the bar over it', () {
    testWidgets('a tab has no way back, and the merchant screen does', (
      WidgetTester tester,
    ) async {
      await _pumpInbox(tester);
      expect(find.byType(MerzoxBackChevron), findsNothing);

      await _pumpInbox(tester, showBack: true);
      expect(find.byType(MerzoxBackChevron), findsOneWidget);
    });

    testWidgets('the magnifier stands clear of the notification bell', (
      WidgetTester tester,
    ) async {
      await _pumpInbox(tester);

      // Found by the key on its button rather than by the mark: the mark is a
      // shared icon now and the field's own copy would match a search for it.
      final Rect glass = tester.getRect(
        find.byKey(const ValueKey<String>('merzox.messages.searchOpen')),
      );

      // The bell floats over this corner on every screen and cannot be moved
      // per screen, so the magnifier stands inboard of it.
      expect(glass.left, greaterThan(_gutter));
      expect(glass.center.dx, lessThan(merzoxGoldenSurfaceSize.width / 2));
    });

    testWidgets('tapping it puts a field where the title was', (
      WidgetTester tester,
    ) async {
      await _pumpInbox(tester);

      expect(find.text('الرسائل'), findsOneWidget);

      await _tapAndSettle(
        tester,
        const ValueKey<String>('merzox.messages.searchOpen'),
      );
      expect(
        find.byKey(const ValueKey<String>('merzox.messages.searchField')),
        findsOneWidget,
      );
      expect(find.text('الرسائل'), findsNothing);
    });

    testWidgets('closing it gives the inbox back', (WidgetTester tester) async {
      await _pumpInbox(tester);

      await _tapAndSettle(
        tester,
        const ValueKey<String>('merzox.messages.searchOpen'),
      );
      await _tapAndSettle(
        tester,
        const ValueKey<String>('merzox.messages.searchClose'),
      );

      expect(find.text('الرسائل'), findsOneWidget);
      expect(find.text('ياسمين خالد'), findsOneWidget);
    });

    testWidgets('an open box with nothing typed still shows the inbox', (
      WidgetTester tester,
    ) async {
      await _pumpInbox(tester);

      await _tapAndSettle(
        tester,
        const ValueKey<String>('merzox.messages.searchOpen'),
      );

      // Asking to search is not asking to be shown nothing.
      expect(find.text('ياسمين خالد'), findsOneWidget);
    });
  }, skip: merzoxGoldenPlatformSkip);
}
