import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/orders/bloc/orders_bloc.dart';
import 'package:merzox/features/orders/bloc/orders_event.dart';
import 'package:merzox/features/orders/pages/orders_page.dart';
import 'package:merzox/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'golden/merzox_golden_harness.dart' as golden;
import 'localization_test_harness.dart';

/// Cancelling an order from `طلباتي`.
///
/// Pressing `إلغاء الطلب` asks for a reason, and answering the question threw
/// a framework assertion onto the screen instead of cancelling anything.

Map<String, dynamic> _order(
  int index, {
  bool canCancel = true,
  String blockedReason = '',
}) => <String, dynamic>{
  'id': '64d00000000000000000010$index',
  'publicId': '22232$index',
  'business': <String, dynamic>{
    'id': '64b000000000000000000009',
    'name': 'متجر الياسمين',
  },
  'items': <Map<String, dynamic>>[
    <String, dynamic>{
      'productId': '64c00000000000000000010$index',
      'variantId': 'v$index',
      'name': 'أساس فت مي',
      'imageUrl': '',
      'unitPrice': 35,
      'quantity': 1,
      'variant': '',
    },
  ],
  'subtotal': 35,
  'deliveryFee': 10,
  'total': 45,
  'currency': 'ILS',
  'deliveryAddress': 'رام الله ، المصيون',
  'paymentMethod': 'cash',
  'status': 'preparing',
  'statusGroup': 'current',
  'statusHistory': const <Map<String, dynamic>>[],
  'cancellationReason': '',
  'createdAt': '2022-01-30T10:00:00.000',
  'courier': const <String, dynamic>{},
  'tracking': <String, dynamic>{
    'isCancelled': false,
    'currentStep': 'placed',
    'currentIndex': 0,
    'steps': const <Map<String, dynamic>>[],
    'courier': const <String, dynamic>{},
    'courierLocation': null,
    'canCancel': canCancel,
    'cancelBlockedReason': blockedReason,
    'canChangeAddress': true,
    'canReview': false,
  },
};

class _OrdersApi extends ApiService {
  /// Whether the server says these orders may still be called off, and if not,
  /// the code it would refuse with.
  final bool canCancel;
  final String blockedReason;

  /// What the screen asked to have cancelled, and why.
  String cancelledId = '';
  String cancelledReason = '';

  _OrdersApi({this.canCancel = true, this.blockedReason = ''});

  @override
  Future<OrderListApiResponse> orders({
    required String token,
    required String status,
    int page = 1,
    int limit = 20,
  }) async => OrderListApiResponse.fromJson(<String, dynamic>{
    'orders': status == 'current'
        ? <Map<String, dynamic>>[
            _order(0, canCancel: canCancel, blockedReason: blockedReason),
            _order(1, canCancel: canCancel, blockedReason: blockedReason),
          ]
        : <Map<String, dynamic>>[],
    'pagination': <String, dynamic>{
      'page': 1,
      'limit': limit,
      'total': status == 'current' ? 2 : 0,
      'hasMore': false,
    },
    'counts': const <String, dynamic>{'total': 2},
  });

  @override
  Future<OrderApiModel> cancelOrder({
    required String token,
    required String orderId,
    String reason = '',
  }) async {
    cancelledId = orderId;
    cancelledReason = reason;
    return OrderApiModel.fromJson(_order(0));
  }
}

Future<_OrdersApi> _pumpOrders(
  WidgetTester tester, {
  bool canCancel = true,
  String blockedReason = '',
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    AuthBloc.sessionKey: true,
    AuthBloc.tokenKey: 'orders-cancel-token',
    AuthBloc.userTypeKey: 'customer',
  });

  final _OrdersApi api = _OrdersApi(
    canCancel: canCancel,
    blockedReason: blockedReason,
  );
  final OrdersBloc bloc = OrdersBloc(apiService: api);
  addTearDown(bloc.close);
  bloc.add(const OrdersStarted());

  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      // The card is laid out against `Tajawal`; the fallback measures wider
      // and overflows the row, and an overflow is an exception that would
      // drown the one this file exists to catch.
      theme: golden.merzoxGoldenTheme(),
      home: BlocProvider<OrdersBloc>.value(
        value: bloc,
        child: const OrdersPage(),
      ),
      builder: (BuildContext context, Widget? child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
    ),
  );
  await settleFrames(tester);

  return api;
}

/// Drags the first card aside, which is what uncovers `إلغاء الطلب`.
Future<void> _revealCancel(WidgetTester tester) async {
  await tester.drag(find.text('أساس فت مي').first, const Offset(140, 0));
  await settleFrames(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
    // The card lays itself out against the real letterforms; the test font
    // measures wider and overflows the row, which would drown the exception
    // this file is here to catch.
    await golden.loadMerzoxGoldenFonts();
    await golden.loadMerzoxGoldenDateSymbols();
  });

  testWidgets('asking to cancel opens the reason box', (tester) async {
    await _pumpOrders(tester);
    await _revealCancel(tester);

    await tester.tap(find.text('orders.cancelOrder'.tr()).first);
    await settleFrames(tester);

    expect(find.text('orders.cancelTitle'.tr()), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirming a cancellation cancels it and says nothing else', (
    tester,
  ) async {
    final _OrdersApi api = await _pumpOrders(tester);
    await _revealCancel(tester);

    await tester.tap(find.text('orders.cancelOrder'.tr()).first);
    await settleFrames(tester);

    await tester.enterText(find.byType(TextField), 'غيرت رأيي');
    await settleFrames(tester);

    await tester.tap(find.text('common.confirm'.tr()));
    await settleFrames(tester);

    expect(
      tester.takeException(),
      isNull,
      reason: 'confirming threw a framework assertion onto the screen',
    );
    expect(api.cancelledId, '64d000000000000000000100');
    expect(api.cancelledReason, 'غيرت رأيي');
  });

  testWidgets('a shut cancel action stays on the card, faded', (tester) async {
    // Taking it away was tried and is worse: a customer who came to call an
    // order off finds nothing at all, and nothing to read is the same "this is
    // broken" as an unexplained refusal, with less to go on.
    await _pumpOrders(tester, canCancel: false);
    await _revealCancel(tester);

    expect(find.text('orders.cancelOrder'.tr()), findsWidgets);

    final FilledButton button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('orders.cancelOrder'.tr()).first,
        matching: find.byType(FilledButton),
      ),
    );
    const Set<WidgetState> resting = <WidgetState>{};

    expect(
      button.style?.backgroundColor?.resolve(resting),
      MerzoxColors.kColorFEE3DC,
      reason: 'the pale ground is what says it is shut',
    );
    expect(
      button.style?.foregroundColor?.resolve(resting),
      MerzoxColors.kColorEE6C4D,
      reason: 'white on the pale ground would not be readable',
    );
    expect(
      button.onPressed,
      isNotNull,
      reason: 'the tap is how the reason is reached',
    );
  });

  testWidgets('pressing the shut action says why, and cancels nothing', (
    tester,
  ) async {
    final _OrdersApi api = await _pumpOrders(
      tester,
      canCancel: false,
      blockedReason: 'ORDER_ALREADY_DISPATCHED',
    );
    await _revealCancel(tester);

    await tester.tap(find.text('orders.cancelOrder'.tr()).first);
    await settleFrames(tester);

    expect(
      find.text('apiErrors.orderAlreadyDispatched'.tr()),
      findsOneWidget,
      reason: 'the same sentence the cancel route would have refused with',
    );
    expect(find.text('orders.cancelTitle'.tr()), findsNothing);
    expect(api.cancelledId, isEmpty);
  });

  testWidgets('a reason the app does not know still says something true', (
    tester,
  ) async {
    // A server that grows a fourth reason must not leave the reader with a
    // blank; the general sentence holds whatever the particular one is.
    await _pumpOrders(tester, canCancel: false, blockedReason: 'SOMETHING_NEW');
    await _revealCancel(tester);

    await tester.tap(find.text('orders.cancelOrder'.tr()).first);
    await settleFrames(tester);

    expect(find.text('apiErrors.orderNotCancellable'.tr()), findsOneWidget);
  });

  testWidgets('backing out of the box cancels nothing', (tester) async {
    final _OrdersApi api = await _pumpOrders(tester);
    await _revealCancel(tester);

    await tester.tap(find.text('orders.cancelOrder'.tr()).first);
    await settleFrames(tester);

    await tester.tap(find.text('common.cancel'.tr()));
    await settleFrames(tester);

    expect(tester.takeException(), isNull);
    expect(api.cancelledId, isEmpty);
  });
}
