import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/secure_token_store.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/cart/bloc/cart_bloc.dart';
import 'package:merzox/features/cart/bloc/cart_event.dart';
import 'package:merzox/features/cart/cart_storage_keys.dart';
import 'package:merzox/features/cart/widgets/cart_items_view.dart';
import 'package:merzox/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'localization_test_harness.dart';

/// The basket tab.
///
/// This is the test the tab could not have: while it was a private widget
/// inside `home_screen`, rendering it meant standing up the whole signed-in
/// home screen, and nothing checked what it actually said. It was telling
/// customers whose order was refused the literal string
/// `orders.checkoutOutOfStock`, because it ran the failure through a helper
/// that only translates keys under `apiErrors.` and hands back everything
/// else untouched.

const String _businessId = '64b000000000000000000001';
const String _productId = '64c000000000000000000001';

class _RefusingApi extends ApiService {
  final String? code;

  _RefusingApi({this.code});

  @override
  Future<BusinessProductApiModel> businessProduct({
    required String businessId,
    required String productId,
  }) {
    throw StateError('offline: the stored line stands');
  }

  @override
  Future<OrderApiModel> createOrder({
    required String token,
    required String businessId,
    required List<OrderItemRequest> items,
    required String deliveryAddress,
    String paymentMethod = 'cash',
    String deliveryOption = 'standard',
    String? clientOrderId,
  }) async {
    throw DioException(
      requestOptions: RequestOptions(path: '/orders'),
      response: Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/orders'),
        statusCode: 400,
        data: <String, dynamic>{
          'success': false,
          if (code != null)
            'error': <String, dynamic>{'code': code, 'message': 'refused'},
        },
      ),
    );
  }
}

void _installSession({bool withBasket = true}) {
  SharedPreferences.setMockInitialValues(<String, Object>{
    AuthBloc.sessionKey: true,
    AuthBloc.userTypeKey: 'normal',
    AuthBloc.addressKey: 'رام الله',
    if (withBasket)
      CartStorageKeys.items: <String>[
        jsonEncode(<String, dynamic>{
          'businessId': _businessId,
          'productId': _productId,
          'name': 'أحمر الشفاه',
          'price': 5,
          'imageUrl': '',
          'quantity': 2,
          'degree': '02',
        }),
      ],
  });
  FlutterSecureStorage.setMockInitialValues(<String, String>{
    SecureTokenStore.key: 'token',
  });
}

Future<CartBloc> _pumpTab(
  WidgetTester tester, {
  required ApiService api,
  bool withBasket = true,
}) async {
  _installSession(withBasket: withBasket);

  final CartBloc bloc = CartBloc(apiService: api)..add(const CartStarted());
  addTearDown(() => bloc.close());

  await pumpLocalized(
    tester,
    BlocProvider<CartBloc>.value(
      value: bloc,
      child: Scaffold(body: CartItemsView(onExplorePressed: () {})),
    ),
  );

  return bloc;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  testWidgets('it shows the basket it was given', (WidgetTester tester) async {
    await _pumpTab(tester, api: _RefusingApi());

    expect(find.text('أحمر الشفاه'), findsOneWidget);
    expect(find.text('nav.cart'.tr()), findsOneWidget);
  });

  testWidgets('an empty basket says so instead of showing a total', (
    WidgetTester tester,
  ) async {
    await _pumpTab(tester, api: _RefusingApi(), withBasket: false);

    expect(find.text('أحمر الشفاه'), findsNothing);
    expect(find.text('home.cart.emptyTitle'.tr()), findsOneWidget);
    expect(find.text('home.cart.exploreShopping'.tr()), findsOneWidget);
  });

  testWidgets('a refused order is told in words, not in a translation key', (
    WidgetTester tester,
  ) async {
    final CartBloc bloc = await _pumpTab(
      tester,
      api: _RefusingApi(code: 'PRODUCT_OUT_OF_STOCK'),
    );

    bloc.add(const CartCheckoutRequested(deliveryAddress: 'رام الله'));
    await settleFrames(tester);

    expect(find.text('orders.checkoutOutOfStock'), findsNothing);
    expect(find.text('orders.checkoutOutOfStock'.tr()), findsOneWidget);
  });

  testWidgets('a reason the app does not model still reaches the customer', (
    WidgetTester tester,
  ) async {
    final CartBloc bloc = await _pumpTab(tester, api: _RefusingApi());

    bloc.add(const CartCheckoutRequested(deliveryAddress: 'رام الله'));
    await settleFrames(tester);

    expect(find.text('orders.checkoutError'), findsNothing);
    expect(find.text('orders.checkoutError'.tr()), findsOneWidget);
  });
}
