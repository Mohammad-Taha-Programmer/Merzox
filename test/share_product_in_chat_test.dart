import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/features/messages/bloc/chat_bloc.dart';
import 'package:merzox/features/messages/bloc/chat_event.dart';
import 'package:merzox/features/messages/pages/chat_page.dart';
import 'package:merzox/features/messages/pages/share_product_page.dart';
import 'package:merzox/features/messages/widgets/shared_product_card.dart';
import 'package:merzox/services/api_service.dart';

import 'catalog_test_fixtures.dart';
import 'localization_test_harness.dart';

/// Sharing a product inside a conversation.
///
/// A merchant points at something on their shelves; a customer points at
/// something they are asking about. What travels is a card - a picture, a
/// name, a price - that leads to the product's own page.
///
/// The rule under all of it belongs to the server and is tested there: the
/// product is looked up inside the shop the conversation belongs to, so
/// neither side can reach into a catalogue that is not part of this thread.
/// What is tested here is that the app never asks for anything else.

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

BusinessProductApiModel _product({
  String id = 'p1',
  String name = 'أحمر الشفاه',
  double price = 5,
}) => catalogProduct(id: id, name: name, price: price);

MessageApiModel _message({
  String id = 'm1',
  String body = '',
  bool isMine = true,
  SharedProductApiModel? shared,
}) => MessageApiModel(
  id: id,
  conversationId: 'c1',
  senderType: isMine ? 'customer' : 'business',
  senderName: 'ياسمين',
  body: body,
  sharedProduct: shared,
  isMine: isMine,
  readAt: null,
  createdAt: DateTime(2026, 9, 6, 9, 40),
);

const SharedProductApiModel _shared = SharedProductApiModel(
  productId: 'p1',
  businessId: 'b1',
  name: 'أحمر الشفاه',
  price: 5,
  imageUrl: '',
);

class _ChatApi extends ApiService {
  final List<MessageApiModel> messages;

  /// What the shelves answered with, and what was asked of them.
  final List<BusinessProductApiModel> shelves;
  final List<String> productsAskedFor = <String>[];

  final List<String> sentBodies = <String>[];
  final List<String?> sentProductIds = <String?>[];

  _ChatApi({this.messages = const <MessageApiModel>[], this.shelves = const []});

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
  Future<List<BusinessProductApiModel>> conversationProducts({
    required String token,
    required String conversationId,
  }) async {
    productsAskedFor.add(conversationId);
    return shelves;
  }

  @override
  Future<MessageApiModel> sendMessage({
    required String token,
    required String conversationId,
    required String body,
    String? productId,
      String? replyToId,
  }) async {
    sentBodies.add(body);
    sentProductIds.add(productId);

    return _message(id: 'm2', body: body, shared: _shared);
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

/// What the picker was asked for, and what it hands back.
class _Picker {
  final BusinessProductApiModel? answer;
  final List<String> askedFor = <String>[];

  _Picker([this.answer]);

  Future<BusinessProductApiModel?> call(
    BuildContext context,
    String conversationId,
  ) async {
    askedFor.add(conversationId);
    return answer;
  }
}

Future<ChatBloc> _openChat(
  WidgetTester tester,
  _ChatApi api, {
  _Picker? picker,
}) async {
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
    BlocProvider<ChatBloc>.value(
      value: bloc,
      child: ChatPage(productPicker: picker?.call),
    ),
  );

  return bloc;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  group('the card in the thread', () {
    testWidgets('a shared product is drawn as a card, not as words', (
      WidgetTester tester,
    ) async {
      await _openChat(
        tester,
        _ChatApi(messages: <MessageApiModel>[_message(shared: _shared)]),
      );

      expect(find.byType(SharedProductCard), findsOneWidget);
      expect(find.text('أحمر الشفاه'), findsOneWidget);
      expect(find.text('₪ 5'), findsOneWidget);
    });

    testWidgets('an ordinary message carries no card', (
      WidgetTester tester,
    ) async {
      await _openChat(
        tester,
        _ChatApi(messages: <MessageApiModel>[_message(body: 'مرحبا')]),
      );

      expect(find.byType(SharedProductCard), findsNothing);
      expect(find.text('مرحبا'), findsOneWidget);
    });

    testWidgets('a card sent with words shows both', (
      WidgetTester tester,
    ) async {
      await _openChat(
        tester,
        _ChatApi(
          messages: <MessageApiModel>[
            _message(body: 'شو رأيك بهذا؟', shared: _shared),
          ],
        ),
      );

      expect(find.byType(SharedProductCard), findsOneWidget);
      expect(find.text('شو رأيك بهذا؟'), findsOneWidget);
    });

    testWidgets('the card is a way in to the product', (
      WidgetTester tester,
    ) async {
      // What it opens is tested where that page is; what matters here is that
      // the card is the thing you press, rather than decoration.
      await _openChat(
        tester,
        _ChatApi(messages: <MessageApiModel>[_message(shared: _shared)]),
      );

      final SharedProductCard card = tester.widget<SharedProductCard>(
        find.byType(SharedProductCard),
      );

      expect(card.onTap, isNotNull);
    });
  });

  group('choosing one', () {
    testWidgets('the button beside send asks for these shelves and no others', (
      WidgetTester tester,
    ) async {
      final _Picker picker = _Picker();
      await _openChat(tester, _ChatApi(), picker: picker);

      await tester.tap(find.byKey(const ValueKey<String>('chat.shareProduct')));
      await settleFrames(tester);

      // The conversation is the only thing named. There is no shop parameter
      // to point at another catalogue with.
      expect(picker.askedFor, <String>['c1']);
    });

    testWidgets('what is chosen waits under the box, and can be taken off', (
      WidgetTester tester,
    ) async {
      final _ChatApi api = _ChatApi();
      await _openChat(tester, api, picker: _Picker(_product()));

      await tester.tap(find.byKey(const ValueKey<String>('chat.shareProduct')));
      await settleFrames(tester);

      // Attached rather than sent, and drawn as the card it will be, with the
      // message box under it: the sender usually has something to ask about
      // what they are pointing at.
      expect(
        find.byKey(const ValueKey<String>('chat.pendingProduct')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('chat.pendingProduct')),
          matching: find.byType(SharedProductCard),
        ),
        findsOneWidget,
      );
      expect(api.sentProductIds, isEmpty);

      await tester.tap(
        find.byKey(const ValueKey<String>('chat.dropPendingProduct')),
      );
      await settleFrames(tester);

      expect(
        find.byKey(const ValueKey<String>('chat.pendingProduct')),
        findsNothing,
      );
    });

    testWidgets('sending carries the product, and only its id', (
      WidgetTester tester,
    ) async {
      final _ChatApi api = _ChatApi();
      await _openChat(tester, api, picker: _Picker(_product()));

      await tester.tap(find.byKey(const ValueKey<String>('chat.shareProduct')));
      await settleFrames(tester);

      await tester.enterText(find.byType(TextField), 'شو رأيك؟');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await settleFrames(tester);

      // The words written under the card travel with it, in that order.
      expect(api.sentBodies, <String>['شو رأيك؟']);
      // The name and the price on the card are the server's to read from the
      // shop; the app never states them.
      expect(api.sentProductIds, <String?>['p1']);

      // And the box is clear again for the next message.
      expect(
        find.byKey(const ValueKey<String>('chat.pendingProduct')),
        findsNothing,
      );
    });

    testWidgets('a card may be sent with nothing written', (
      WidgetTester tester,
    ) async {
      // Pointing at something is a message. The send used to refuse an empty
      // box outright.
      final _ChatApi api = _ChatApi();
      await _openChat(tester, api, picker: _Picker(_product()));

      await tester.tap(find.byKey(const ValueKey<String>('chat.shareProduct')));
      await settleFrames(tester);

      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await settleFrames(tester);

      expect(api.sentBodies, <String>['']);
      expect(api.sentProductIds, <String?>['p1']);
    });

    testWidgets('an empty box with nothing attached sends nothing', (
      WidgetTester tester,
    ) async {
      final _ChatApi api = _ChatApi();
      await _openChat(tester, api);

      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await settleFrames(tester);

      expect(api.sentBodies, isEmpty);
    });
  });

  group('who is looking at a shared card', () {
    test('the merchant side of a thread is the shop that sells it', () {
      // Only this conversation's shop can be shared from, so a reader on the
      // merchant side is that shop - and the product page freezes its
      // stepper, its cart and its buy button for them.
      expect(
        viewerOwnsSharedProduct(
          const AuthSessionSnapshot(
            type: AuthSessionType.business,
            ownsBusiness: true,
            token: 't',
          ),
        ),
        isTrue,
      );
    });

    test('a shop owner who turned to the customer side is a customer', () {
      // They buy from other shops that way, and this is one of those threads.
      expect(
        viewerOwnsSharedProduct(
          const AuthSessionSnapshot(
            type: AuthSessionType.customer,
            ownsBusiness: true,
            token: 't',
          ),
        ),
        isFalse,
      );
    });

    test('and an ordinary customer keeps every button', () {
      expect(
        viewerOwnsSharedProduct(
          const AuthSessionSnapshot(
            type: AuthSessionType.customer,
            token: 't',
          ),
        ),
        isFalse,
      );
    });
  });

  group('the shelves', () {
    testWidgets('a shop with nothing to share says so', (
      WidgetTester tester,
    ) async {
      await pumpLocalized(
        tester,
        ShareProductPage(
          conversationId: 'c1',
          apiService: _ChatApi(),
          authSessionService: const _Session(),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await settleFrames(tester);

      expect(find.text('لا توجد منتجات لمشاركتها.'), findsOneWidget);
    });

    testWidgets('every product is offered to be pointed at', (
      WidgetTester tester,
    ) async {
      await pumpLocalized(
        tester,
        ShareProductPage(
          conversationId: 'c1',
          apiService: _ChatApi(
            shelves: <BusinessProductApiModel>[
              _product(),
              _product(id: 'p2', name: 'كحل', price: 12),
            ],
          ),
          authSessionService: const _Session(),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await settleFrames(tester);

      expect(find.text('أحمر الشفاه'), findsOneWidget);
      expect(find.text('كحل'), findsOneWidget);
      expect(find.text('₪ 12'), findsOneWidget);
    });
  });
}
