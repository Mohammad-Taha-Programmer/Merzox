import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/features/business/orders/merchant_order_detail_page.dart';
import 'package:merzox/features/business/orders/merchant_order_route.dart';
import 'package:merzox/features/business/shell/business_bloc.dart';
import 'package:merzox/services/api_service.dart';

import 'auth_session_fixtures.dart';
import 'golden/merzox_golden_harness.dart';
import 'localization_test_harness.dart';

/// Where a merchant lands when they tap "you have a new order".
///
/// They were sent to the customer's tracking screen, which looks an order up
/// among the reader's own purchases. A merchant has none, so the app told them
/// their own shop's order did not exist - with the order sitting in their list
/// the whole time. It was being asked for from the wrong side.

const String _orderId = '64d000000000000000000201';

Map<String, dynamic> _orderJson({String id = _orderId}) => <String, dynamic>{
  'id': id,
  'publicId': '222321',
  'customerName': 'ياسمين خالد',
  'customerPhone': '0592029316',
  'items': <Map<String, dynamic>>[
    <String, dynamic>{
      'productId': '64c000000000000000000201',
      'variantId': null,
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
  'deliveryAddress': 'أريحا',
  'paymentMethod': 'cash',
  'status': 'pending',
  'statusGroup': 'current',
  'statusHistory': const <Map<String, dynamic>>[],
  'cancellationReason': '',
  'createdAt': '2022-02-15T10:00:00.000',
  'courier': const <String, dynamic>{},
};

class _ShopApi extends ApiService {
  /// What the merchant's own order list holds.
  List<Map<String, dynamic>> shopOrders = <Map<String, dynamic>>[_orderJson()];

  int loads = 0;

  @override
  Future<OwnerBusiness> ownerBusiness({required String token}) async =>
      OwnerBusiness.fromJson(const <String, dynamic>{
        'id': 'b1',
        'name': 'متجر الياسمين',
        'address': 'رام الله',
      });

  @override
  Future<AuthApiUser> me({required String token}) async =>
      AuthApiUser.fromJson(const <String, dynamic>{'id': 'u1', 'name': 'تاجر'});

  @override
  Future<BusinessDashboardData> businessDashboard({
    required String token,
    DateTime? from,
    DateTime? to,
  }) async => BusinessDashboardData.fromJson(const <String, dynamic>{});

  @override
  Future<List<OwnerProduct>> ownerProducts({required String token}) async =>
      const <OwnerProduct>[];

  @override
  Future<OwnerOrderList> ownerOrders({
    required String token,
    String statusGroup = '',
    MerchantOrderFilter filter = const MerchantOrderFilter(),
    int page = 1,
    int limit = 20,
  }) async {
    loads += 1;
    return OwnerOrderList.fromJson(<String, dynamic>{'orders': shopOrders});
  }
}

/// An API that never answers, for the state between asking and knowing.
class _SilentApi extends _ShopApi {
  @override
  Future<OwnerOrderList> ownerOrders({
    required String token,
    String statusGroup = '',
    MerchantOrderFilter filter = const MerchantOrderFilter(),
    int page = 1,
    int limit = 20,
  }) => Completer<OwnerOrderList>().future;
}

Future<void> _pumpRoute(
  WidgetTester tester,
  _ShopApi api, {
  String orderId = _orderId,
}) async {
  useAuthenticatedSession(business: true);

  await pumpMerzoxGoldenPage(
    tester,
    withMerzoxGoldenDeviceInsets(
      MerchantOrderRoute(
        orderId: orderId,
        blocBuilder: () => BusinessBloc(apiService: api),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
    // The golden harness's fonts, not the plain one's: without them Flutter
    // lays Arabic out in a fallback face whose glyphs are all the same wide
    // box, and rows overflow here that do not overflow on a phone.
    await loadMerzoxGoldenFonts();
  });

  testWidgets('an order of this shop opens on the merchant screen', (
    WidgetTester tester,
  ) async {
    await _pumpRoute(tester, _ShopApi());

    // The merchant's own screen, not the customer's tracking one: it is the
    // one with the status control and the invoice on it.
    expect(find.byType(MerchantOrderDetailPage), findsOneWidget);
    expect(find.text('حالة الطلب'), findsOneWidget);
  });

  testWidgets('it says nothing while the list is still arriving', (
    WidgetTester tester,
  ) async {
    useAuthenticatedSession(business: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: MerchantOrderRoute(
            orderId: _orderId,
            // Never answers, so the screen is held in the state it shows
            // while the list is on its way.
            blocBuilder: () => BusinessBloc(apiService: _SilentApi()),
          ),
        ),
      ),
    );
    await tester.pump();

    // Announcing "not found" before anything has loaded is exactly how the old
    // screen was wrong.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('merchantOrder.notFound')),
      findsNothing,
    );
  });

  testWidgets('an order that is not this shop is said so, once it is known', (
    WidgetTester tester,
  ) async {
    final _ShopApi api = _ShopApi()..shopOrders = <Map<String, dynamic>>[];

    await _pumpRoute(tester, api);

    expect(
      find.byKey(const ValueKey<String>('merchantOrder.notFound')),
      findsOneWidget,
    );
    expect(find.byType(MerchantOrderDetailPage), findsNothing);
  });

  testWidgets('an id belonging to some other shop resolves to nothing', (
    WidgetTester tester,
  ) async {
    await _pumpRoute(tester, _ShopApi(), orderId: 'not-this-shops-order');

    expect(
      find.byKey(const ValueKey<String>('merchantOrder.notFound')),
      findsOneWidget,
    );
  });

  testWidgets('the retry asks the server again', (WidgetTester tester) async {
    final _ShopApi api = _ShopApi()..shopOrders = <Map<String, dynamic>>[];

    await _pumpRoute(tester, api);
    final int before = api.loads;

    await tester.tap(find.byType(OutlinedButton));
    // The refresh reads the session before it reaches the server, and that
    // read only runs on the real event loop.
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await settleFrames(tester);

    expect(api.loads, greaterThan(before));
  });

  testWidgets('the screen it opens is wired to the merchant own bloc', (
    WidgetTester tester,
  ) async {
    await _pumpRoute(tester, _ShopApi());

    // The shell reaches the same view a different way; both must get a bloc,
    // because every action on the screen is dispatched through it.
    final BuildContext context = tester.element(
      find.byType(MerchantOrderDetailPage),
    );
    expect(BlocProvider.of<BusinessBloc>(context), isNotNull);
  });
}
