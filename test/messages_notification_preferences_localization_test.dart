import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/features/messages/bloc/chat_bloc.dart';
import 'package:merzox/features/messages/bloc/chat_event.dart';
import 'package:merzox/features/messages/bloc/chat_state.dart';
import 'package:merzox/features/messages/pages/chat_page.dart';
import 'package:merzox/features/notification_preferences/bloc/notification_preference_bloc.dart';
import 'package:merzox/features/notification_preferences/bloc/notification_preference_event.dart';
import 'package:merzox/features/notification_preferences/bloc/notification_preference_state.dart';
import 'package:merzox/features/notification_preferences/widgets/notification_preference_control.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/services/notification_preference_service.dart';

import 'auth_session_fixtures.dart';
import 'localization_test_harness.dart';

ConversationApiModel _conversation() {
  return ConversationApiModel(
    id: 'c1',
    title: 'Test store',
    avatarUrl: '',
    business: const ConversationPartyApiModel(
      id: 'b1',
      name: 'Test store',
      logoUrl: '',
    ),
    customer: null,
    lastMessage: ConversationLastMessageApiModel(
      body: 'Incoming message',
      senderType: 'business',
      sentAt: DateTime.utc(2026, 8, 25, 10),
    ),
    unreadCount: 0,
    messageCount: 2,
    updatedAt: DateTime.utc(2026, 8, 25, 10),
  );
}

MessageApiModel _message({
  required String id,
  required String body,
  required bool isMine,
}) {
  return MessageApiModel(
    id: id,
    conversationId: 'c1',
    senderType: isMine ? 'customer' : 'business',
    senderName: isMine ? 'Customer' : 'Test store',
    body: body,
    isMine: isMine,
    readAt: null,
    createdAt: DateTime.utc(2026, 8, 25, 10),
  );
}

class _ChatLocalizationApi extends ApiService {
  @override
  Future<ConversationMessagesApiResponse> conversationMessages({
    required String token,
    required String conversationId,
    int page = 1,
    int limit = 30,
  }) async {
    return ConversationMessagesApiResponse(
      conversation: _conversation(),
      messages: [
        _message(id: 'incoming', body: 'Incoming message', isMine: false),
        _message(id: 'mine', body: 'My message', isMine: true),
      ],
      page: page,
      hasMore: false,
    );
  }

  @override
  Future<ConversationApiModel> markConversationRead({
    required String token,
    required String conversationId,
  }) async {
    return _conversation();
  }
}

class _PreferenceLocalizationGateway implements NotificationPreferenceGateway {
  bool productOffers = true;
  Object? loadError;
  Object? updateError;

  int updateCalls = 0;

  @override
  Future<NotificationPreferenceSnapshot> load({required String token}) async {
    if (loadError != null) {
      throw loadError!;
    }

    return NotificationPreferenceSnapshot(productOffers: productOffers);
  }

  @override
  Future<NotificationPreferenceSnapshot> update({
    required String token,
    required bool value,
    String key = NotificationPreferenceKeys.productOffers,
  }) async {
    updateCalls += 1;

    if (updateError != null) {
      throw updateError!;
    }

    productOffers = value;

    return NotificationPreferenceSnapshot(productOffers: value);
  }
}

Future<AuthSessionSnapshot> _preferenceSession() async {
  return const AuthSessionSnapshot(
    type: AuthSessionType.customer,
    token: 'preference-token',
  );
}

void _expectDirection(
  WidgetTester tester,
  Finder finder,
  TextDirection direction,
) {
  expect(finder, findsOneWidget);
  expect(Directionality.of(tester.element(finder)), direction);
}

BorderRadius _bubbleRadius(
  WidgetTester tester,
  String body,
  TextDirection direction,
) {
  final containers = find.ancestor(
    of: find.text(body),
    matching: find.byType(Container),
  );

  for (final element in containers.evaluate()) {
    final widget = element.widget;

    if (widget is! Container) {
      continue;
    }

    final decoration = widget.decoration;

    if (decoration is! BoxDecoration) {
      continue;
    }

    final radius = decoration.borderRadius;

    if (radius is BorderRadiusDirectional) {
      return radius.resolve(direction);
    }
  }

  throw StateError('Could not find directional message bubble for "$body"');
}

void _expectLogicalTail({
  required BorderRadius radius,
  required bool mine,
  required TextDirection direction,
}) {
  // `الرسائل – 2` puts what you wrote at the logical START and what you were
  // told at the end, and the tail is the corner pointing back at whoever
  // spoke: a mine bubble's small corner is at its own end.
  final smallOnLeft = mine
      ? direction == TextDirection.ltr
      : direction == TextDirection.rtl;

  expect(radius.bottomLeft.x, closeTo(smallOnLeft ? 2 : 14, 0.001));

  expect(radius.bottomRight.x, closeTo(smallOnLeft ? 14 : 2, 0.001));
}

Future<ChatBloc> _pumpReadyChat(
  WidgetTester tester, {
  required TextDirection direction,
}) async {
  useAuthenticatedSession();

  final bloc = ChatBloc(
    apiService: _ChatLocalizationApi(),
    conversationId: 'c1',
  );

  addTearDown(bloc.close);

  final ready = bloc.stream.firstWhere(
    (state) => state.status == ChatStatus.ready && state.messages.length == 2,
  );

  bloc.add(const ChatStarted());

  await ready;

  await pumpLocalized(
    tester,
    BlocProvider.value(value: bloc, child: const ChatPage()),
    textDirection: direction,
  );

  return bloc;
}

Future<NotificationPreferenceBloc> _pumpPreference(
  WidgetTester tester, {
  required TextDirection direction,
  required _PreferenceLocalizationGateway gateway,
}) async {
  final bloc = NotificationPreferenceBloc(
    gateway: gateway,
    sessionReader: _preferenceSession,
  );

  addTearDown(bloc.close);

  await pumpLocalized(
    tester,
    BlocProvider.value(
      value: bloc,
      child: const Scaffold(body: NotificationPreferenceControl()),
    ),
    textDirection: direction,
  );

  final resolved = bloc.stream.firstWhere(
    (state) =>
        state.status == NotificationPreferenceStatus.ready ||
        state.status == NotificationPreferenceStatus.failure,
  );

  bloc.add(const NotificationPreferenceStarted());

  await resolved;
  await settleFrames(tester);

  return bloc;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final language in ['ar', 'en']) {
    group('GAP-015E $language localization', () {
      setUpAll(() async {
        await loadAppTranslations(languageCode: language);
      });

      final isArabic = language == 'ar';

      final direction = isArabic ? TextDirection.rtl : TextDirection.ltr;

      testWidgets('controlled chat open error is localized', (tester) async {
        final bloc = ChatBloc();

        addTearDown(bloc.close);

        final failure = bloc.stream.firstWhere(
          (state) => state.status == ChatStatus.failure,
        );

        bloc.add(const ChatStarted());

        await failure;

        await pumpLocalized(
          tester,
          BlocProvider.value(value: bloc, child: const ChatPage()),
          textDirection: direction,
        );

        final expected = isArabic
            ? 'تعذر فتح المحادثة'
            : 'Could not open the conversation';

        expect(find.text(expected), findsOneWidget);

        _expectDirection(tester, find.text(expected), direction);
      });

      testWidgets('message bubble tails resolve to logical sender side', (
        tester,
      ) async {
        await _pumpReadyChat(tester, direction: direction);

        expect(find.text('Incoming message'), findsOneWidget);

        expect(find.text('My message'), findsOneWidget);

        final incoming = _bubbleRadius(tester, 'Incoming message', direction);

        final mine = _bubbleRadius(tester, 'My message', direction);

        _expectLogicalTail(radius: incoming, mine: false, direction: direction);

        _expectLogicalTail(radius: mine, mine: true, direction: direction);
      });

      testWidgets(
        'notification preference label uses logical start and control uses end',
        (tester) async {
          final gateway = _PreferenceLocalizationGateway();

          await _pumpPreference(tester, direction: direction, gateway: gateway);

          final label = isArabic
              ? 'تنبيهات المنتجات والعروض'
              : 'Product and offer notifications';

          expect(find.text(label), findsOneWidget);

          _expectDirection(tester, find.text(label), direction);

          final iconX = tester
              .getCenter(find.byIcon(Icons.notifications_none_rounded))
              .dx;

          final switchX = tester.getCenter(find.byType(Switch)).dx;

          if (isArabic) {
            expect(iconX, greaterThan(switchX));
          } else {
            expect(iconX, lessThan(switchX));
          }
        },
      );

      testWidgets('notification preference retry is localized at logical end', (
        tester,
      ) async {
        final gateway = _PreferenceLocalizationGateway()
          ..loadError = StateError('offline');

        await _pumpPreference(tester, direction: direction, gateway: gateway);

        final retry = isArabic ? 'إعادة المحاولة' : 'Try again';

        expect(find.text(retry), findsOneWidget);

        expect(find.byType(Switch), findsNothing);

        final iconX = tester
            .getCenter(find.byIcon(Icons.notifications_none_rounded))
            .dx;

        final retryX = tester.getCenter(find.text(retry)).dx;

        if (isArabic) {
          expect(iconX, greaterThan(retryX));
        } else {
          expect(iconX, lessThan(retryX));
        }
      });

      testWidgets('failed preference save surfaces localized stable error', (
        tester,
      ) async {
        final gateway = _PreferenceLocalizationGateway()
          ..updateError = StateError('offline');

        final bloc = await _pumpPreference(
          tester,
          direction: direction,
          gateway: gateway,
        );

        final error = bloc.stream.firstWhere(
          (state) => state.errorMessage.isNotEmpty,
        );

        final toggle = tester.widget<Switch>(find.byType(Switch));

        expect(toggle.onChanged, isNotNull);

        toggle.onChanged!(!toggle.value);

        await error;
        await settleFrames(tester);

        final expected = isArabic
            ? 'تعذر حفظ تفضيل التنبيهات. لم يتم تغيير الإعداد.'
            : 'Could not save notification preferences. The setting was not changed.';

        expect(find.text(expected), findsOneWidget);

        expect(gateway.updateCalls, 1);
      });
    });
  }
}
