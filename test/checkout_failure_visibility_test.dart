import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/secure_token_store.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/cart/bloc/cart_bloc.dart';
import 'package:merzox/features/cart/bloc/cart_event.dart';
import 'package:merzox/features/cart/cart_storage_keys.dart';
import 'package:merzox/features/checkout/pages/checkout_page.dart';
import 'package:merzox/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'localization_test_harness.dart';

/// What the customer is told when an order will not go through.
///
/// A real one cost hours: the server refused every order over a field the two
/// sides disagreed about, and this screen said nothing at all - no message, no
/// spinner, no movement. The failure reached the state and stopped there,
/// because the screen only listened for success and never rendered
/// `errorMessage` anywhere. From the outside, a refused order and a dead
/// button are the same thing.

const String _businessId = '64b000000000000000000001';
const String _productId = '64c000000000000000000001';

/// Refuses every order with [code], and refuses to re-read the cart line so
/// the stored snapshot survives into checkout.
class _RefusingApi extends ApiService {
  final String code;

  _RefusingApi(this.code);

  @override
  Future<DeliveryOptionsApiResponse> deliveryOptions() async {
    return const DeliveryOptionsApiResponse(
      options: <DeliveryOptionApiModel>[
        DeliveryOptionApiModel(option: 'standard', fee: 10),
        DeliveryOptionApiModel(option: 'express', fee: 30),
      ],
      defaultOption: 'standard',
    );
  }

  @override
  Future<List<SavedAddressApiModel>> myAddresses({required String token}) {
    // No address book: the step falls back to the profile's stored line, which
    // is the shape most of these accounts are in.
    throw StateError('no address book');
  }

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
          'error': <String, dynamic>{'code': code, 'message': 'refused'},
        },
      ),
    );
  }
}

void _installBasket() {
  SharedPreferences.setMockInitialValues(<String, Object>{
    AuthBloc.sessionKey: true,
    AuthBloc.userTypeKey: 'normal',
    AuthBloc.addressKey: 'رام الله',
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

/// Walks the screen to the payment step and presses confirm.
Future<void> _confirmAnOrder(WidgetTester tester, ApiService api) async {
  _installBasket();

  final CartBloc bloc = CartBloc(apiService: api)..add(const CartStarted());
  addTearDown(() => bloc.close());

  await pumpLocalized(
    tester,
    BlocProvider<CartBloc>.value(
      value: bloc,
      child: CheckoutPage(apiService: api, onCompleted: () {}),
    ),
  );

  await tester.tap(find.text('checkout.continue'.tr()));
  await settleFrames(tester);

  await tester.tap(find.text('checkout.confirm'.tr()));
  await settleFrames(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  testWidgets('a refused order says why, in words the customer can act on', (
    WidgetTester tester,
  ) async {
    await _confirmAnOrder(tester, _RefusingApi('PRODUCT_OUT_OF_STOCK'));

    expect(
      find.text('orders.checkoutOutOfStock'.tr()),
      findsOneWidget,
      reason: 'the reason the server gave must reach the customer',
    );
  });

  testWidgets('a reason nobody models still produces a message', (
    WidgetTester tester,
  ) async {
    await _confirmAnOrder(tester, _RefusingApi('SOME_CODE_ADDED_LATER'));

    expect(find.text('orders.checkoutError'.tr()), findsOneWidget);
  });

  testWidgets('the message is written, never a raw translation key', (
    WidgetTester tester,
  ) async {
    await _confirmAnOrder(tester, _RefusingApi('INVALID_ORDER_FIELDS'));

    expect(find.text('orders.checkoutRejectedShape'), findsNothing);
    expect(find.text('orders.checkoutRejectedShape'.tr()), findsOneWidget);
  });
}
