import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_bloc.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_event.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_state.dart';
import 'package:merzox/features/business_profile/business_profile_view_mode.dart';
import 'package:merzox/features/business_profile/pages/business_profile_page.dart';
import 'package:merzox/features/cart/bloc/cart_bloc.dart';
import 'package:merzox/features/cart/bloc/cart_event.dart';
import 'package:merzox/features/cart/bloc/cart_state.dart';
import 'package:merzox/features/cart/cart_storage_keys.dart';
import 'package:merzox/features/home/presentation/bloc/home_state_.dart';
import 'package:merzox/features/product_details/bloc/product_details_bloc.dart';
import 'package:merzox/features/product_details/bloc/product_details_event.dart';
import 'package:merzox/features/product_details/bloc/product_details_state.dart';
import 'package:merzox/features/product_details/pages/product_details_page.dart';
import 'package:merzox/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_session_fixtures.dart';
import 'catalog_test_fixtures.dart';
import 'localization_test_harness.dart';

/// MERZOX-GAP-002 commerce truth, client side.
///
/// Three claims are under test:
///
///   1. the customer model carries the PUBLIC commerce contract - the sale
///      price and availability - and none of the merchant-private figures,
///   2. what the customer sees and what the cart stores is the sale price,
///   3. an out-of-stock product cannot be bought, and a failed checkout stays
///      visibly failed with the cart intact.

const _businessId = '64b000000000000000000001';
const _productId = '64c000000000000000000001';

// --------------------------------------------------------------------- fakes

class _CommerceApi extends ApiService {
  final List<String> calls = [];

  BusinessProductApiModel product = catalogProduct();
  Object? checkoutError;
  int createOrderCalls = 0;
  int productReadCalls = 0;

  @override
  Future<BusinessProductApiModel> businessProduct({
    required String businessId,
    required String productId,
  }) async {
    productReadCalls += 1;
    calls.add('GET /businesses/$businessId/products/$productId');
    return product;
  }

  @override
  Future<List<BusinessReviewApiModel>> productReviews({
    required String businessId,
    required String productId,
  }) async => const [];

  @override
  Future<BusinessDetailApiModel> business({required String businessId}) async =>
      catalogBusinessDetail(id: businessId);

  @override
  Future<List<BusinessProductApiModel>> businessProducts({
    required String businessId,
    required String classification,
  }) async => [product];

  @override
  Future<List<BusinessReviewApiModel>> businessReviews({
    required String businessId,
  }) async => const [];

  @override
  Future<FavoriteStatusApiResponse> favoriteStatus({
    required String token,
    required String businessId,
  }) async => const FavoriteStatusApiResponse(
    businessFavorited: false,
    productIds: <String>{},
  );

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
    createOrderCalls += 1;
    calls.add('POST /orders');
    final failure = checkoutError;
    if (failure != null) throw failure;

    throw StateError('no order fixture was configured');
  }
}

/// The exact envelope `errorHandler.js` returns, so the client is tested
/// against the shape the server actually sends.
DioException _serverRefusal(String code, {int status = 409}) {
  final request = RequestOptions(path: '/orders');

  return DioException(
    requestOptions: request,
    response: Response<Map<String, dynamic>>(
      requestOptions: request,
      statusCode: status,
      data: {
        'success': false,
        'error': {'code': code, 'message': 'refused'},
      },
    ),
  );
}

Map<String, dynamic> _cartEntry({
  double price = 25,
  int quantity = 1,
  String name = 'Test product',
}) {
  return {
    'businessId': _businessId,
    'productId': _productId,
    'name': name,
    'price': price,
    'imageUrl': '',
    'quantity': quantity,
  };
}

Future<ProductDetailsBloc> _startedDetails(_CommerceApi api) async {
  final bloc = ProductDetailsBloc(apiService: api);
  final ready = bloc.stream.firstWhere(
    (state) => state.status == ProductDetailsStatus.ready,
  );
  bloc.add(
    ProductDetailsStarted(businessId: _businessId, initialProduct: api.product),
  );
  await ready;

  return bloc;
}

Widget _detailsPage(ProductDetailsBloc bloc, BusinessProductApiModel product) {
  return ProductDetailsPage(
    business: const HomeBusiness(
      id: _businessId,
      name: 'متجر',
      category: 'فئة',
      products: [],
      rating: 0,
      colorValue: 0xffdeeef8,
    ),
    product: product,
    bloc: bloc,
  );
}

Future<void> drainMicrotasks({int turns = 20}) async {
  for (var turn = 0; turn < turns; turn += 1) {
    await Future<void>.value();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadAppTranslations);

  setUp(() => useAuthenticatedSession());

  group('the public product contract', () {
    test('F01/F02/F03 - discount, sale price and availability are parsed', () {
      final product = BusinessProductApiModel.fromJson(
        catalogProductJson(price: 100, discountPercent: 25, finalPrice: 75),
      );

      expect(product.discountPercent, 25);
      expect(product.finalPrice, 75);
      expect(product.inStock, isTrue);
      expect(product.hasDiscount, isTrue);
      // The payable price, and it is NOT the list price.
      expect(product.displayPrice, 75);
      expect(product.displayPrice, isNot(product.price));
    });

    test('an undiscounted product reports no discount', () {
      final product = BusinessProductApiModel.fromJson(
        catalogProductJson(price: 40),
      );

      expect(product.discountPercent, 0);
      expect(product.finalPrice, 40);
      expect(product.hasDiscount, isFalse);
      expect(product.displayPrice, product.price);
    });

    test('F03 - availability comes from the server, never assumed', () {
      final product = BusinessProductApiModel.fromJson(
        catalogProductJson(inStock: false),
      );

      expect(product.inStock, isFalse);
    });

    test(
      'F04 - a malformed price, sale price or stock flag breaks the contract',
      () {
        final broken = <String, Map<String, dynamic>>{
          'missing price': catalogProductJson()..remove('price'),
          'missing finalPrice': catalogProductJson()..remove('finalPrice'),
          'missing inStock': catalogProductJson()..remove('inStock'),
          'string price': catalogProductJson()..['price'] = '25',
          'string finalPrice': catalogProductJson()..['finalPrice'] = 'free',
          'negative finalPrice': catalogProductJson()..['finalPrice'] = -1,
          'string inStock': catalogProductJson()..['inStock'] = 'yes',
          'out of range discount': catalogProductJson()
            ..['discountPercent'] = 150,
        };

        broken.forEach((reason, payload) {
          expect(
            () => BusinessProductApiModel.fromJson(payload),
            throwsA(isA<ApiContractException>()),
            reason: reason,
          );
        });
      },
    );

    test(
      'F05/F06/F07 - merchant-private figures cannot reach the customer model',
      () {
        // Present in the payload, and expected to be dropped at parse time.
        final product = BusinessProductApiModel.fromJson(
          catalogProductJson(price: 100, discountPercent: 25, finalPrice: 75)
            ..addAll(const {
              'costPrice': 41.25,
              'stockQuantity': 137,
              'unlimitedStock': false,
              'keywords': ['private-merchant-keyword'],
            }),
        );

        final reachable = <Object?>[
          product.id,
          product.name,
          product.description,
          product.price,
          product.discountPercent,
          product.finalPrice,
          product.inStock,
          product.imageUrl,
          ...product.imageUrls,
          product.classification,
          product.rating,
          product.ratingCount,
          product.likeCount,
          product.isService,
        ].map((value) => value.toString()).toList();

        expect(reachable, isNot(contains('41.25')));
        expect(reachable, isNot(contains('137')));
        expect(reachable, isNot(contains('private-merchant-keyword')));
      },
    );

    test(
      'F16/F17/F18 - store, search and favourites share one price semantic',
      () {
        final payload = catalogProductJson(
          price: 100,
          discountPercent: 25,
          finalPrice: 75,
        );

        // Search and favourites both wrap the SAME public model, so a
        // discounted product cannot read one price here and another there.
        final storefront = BusinessProductApiModel.fromJson(payload);
        final search = SearchProductApiModel.fromJson({
          ...payload,
          'business': <String, dynamic>{'id': _businessId, 'name': 'متجر'},
        }).product;
        final favorite = FavoriteProductApiModel.fromJson({
          'product': payload,
          'business': <String, dynamic>{'id': _businessId, 'name': 'متجر'},
        }).product;

        for (final product in [search, favorite]) {
          expect(product.displayPrice, storefront.displayPrice);
          expect(product.finalPrice, storefront.finalPrice);
          expect(product.discountPercent, storefront.discountPercent);
          expect(product.inStock, storefront.inStock);
          expect(product.hasDiscount, storefront.hasDiscount);
        }
      },
    );
  });

  group('product details commerce', () {
    testWidgets('F08 - a discounted product shows the sale price', (
      tester,
    ) async {
      final api = _CommerceApi()
        ..product = catalogProduct(
          price: 100,
          discountPercent: 25,
          finalPrice: 75,
        );
      final bloc = await _startedDetails(api);

      await pumpLocalized(tester, _detailsPage(bloc, api.product));

      expect(find.text('₪ 75'), findsOneWidget);
      // The list price stays visible as the struck-through comparison.
      expect(find.text('₪ 100'), findsOneWidget);
    });

    testWidgets('F09 - an undiscounted product shows one plain price', (
      tester,
    ) async {
      final api = _CommerceApi()..product = catalogProduct(price: 40);
      final bloc = await _startedDetails(api);

      await pumpLocalized(tester, _detailsPage(bloc, api.product));

      expect(find.text('₪ 40'), findsOneWidget);
      expect(find.byType(FilledButton), findsWidgets);
    });

    testWidgets('F10/F11 - out of stock removes both commerce actions', (
      tester,
    ) async {
      final api = _CommerceApi()..product = catalogProduct(inStock: false);
      final bloc = await _startedDetails(api);

      await pumpLocalized(tester, _detailsPage(bloc, api.product));

      expect(find.text('غير متوفر حالياً'), findsOneWidget);
      expect(find.text('أضف إلى السلة'), findsNothing);
      expect(find.text('شراء الآن'), findsNothing);
    });

    testWidgets('F20 - an in-stock product keeps both commerce actions', (
      tester,
    ) async {
      final api = _CommerceApi()..product = catalogProduct();
      final bloc = await _startedDetails(api);

      await pumpLocalized(tester, _detailsPage(bloc, api.product));

      expect(find.text('أضف إلى السلة'), findsOneWidget);
      expect(find.text('شراء الآن'), findsOneWidget);
      expect(find.text('غير متوفر حالياً'), findsNothing);
    });

    test('F12 - an out-of-stock add-to-cart event writes nothing', () async {
      SharedPreferences.setMockInitialValues({
        AuthBloc.sessionKey: true,
        AuthBloc.tokenKey: 'real-token',
        CartStorageKeys.items: <String>[],
      });
      final api = _CommerceApi()..product = catalogProduct(inStock: false);
      final bloc = await _startedDetails(api);
      addTearDown(bloc.close);

      final failed = bloc.stream.firstWhere(
        (state) => state.status == ProductDetailsStatus.failure,
      );
      bloc.add(const ProductDetailsAddToCartPressed());
      final state = await failed;

      expect(state.errorMessage, 'catalog.outOfStock');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(CartStorageKeys.items), isEmpty);
    });

    test('F12 - an out-of-stock buy-now event creates no order', () async {
      final api = _CommerceApi()..product = catalogProduct(inStock: false);
      final bloc = await _startedDetails(api);
      addTearDown(bloc.close);

      final failed = bloc.stream.firstWhere(
        (state) => state.status == ProductDetailsStatus.failure,
      );
      bloc.add(const ProductDetailsBuyNowPressed());
      final state = await failed;

      expect(state.errorMessage, 'catalog.outOfStock');
      expect(api.createOrderCalls, 0);
    });

    test('F13 - a new cart entry snapshots the sale price', () async {
      SharedPreferences.setMockInitialValues({
        AuthBloc.sessionKey: true,
        AuthBloc.tokenKey: 'real-token',
        CartStorageKeys.items: <String>[],
      });
      final api = _CommerceApi()
        ..product = catalogProduct(
          price: 100,
          discountPercent: 25,
          finalPrice: 75,
        );
      final bloc = await _startedDetails(api);
      addTearDown(bloc.close);

      final added = bloc.stream.firstWhere(
        (state) => state.status == ProductDetailsStatus.action,
      );
      bloc.add(const ProductDetailsAddToCartPressed());
      await added;

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(CartStorageKeys.items)!;
      final entry = jsonDecode(stored.single) as Map<String, dynamic>;

      expect(entry['price'], 75);
      expect(entry['price'], isNot(100));
    });

    test('F14 - a stock refusal from the server stays observable', () async {
      final api = _CommerceApi()
        ..product = catalogProduct()
        ..checkoutError = _serverRefusal('INSUFFICIENT_STOCK');
      final bloc = await _startedDetails(api);
      addTearDown(bloc.close);

      final failed = bloc.stream.firstWhere(
        (state) => state.status == ProductDetailsStatus.failure,
      );
      bloc.add(const ProductDetailsBuyNowPressed());
      final state = await failed;

      // Not collapsed into a generic checkout error.
      expect(state.errorMessage, 'orders.checkoutInsufficientStock');
      expect(api.createOrderCalls, 1);
    });
  });

  group('cart truthfulness', () {
    test('the cart refreshes each line from the public contract', () async {
      SharedPreferences.setMockInitialValues({
        AuthBloc.sessionKey: true,
        AuthBloc.tokenKey: 'real-token',
        // A stale snapshot: the merchant has since discounted the product.
        CartStorageKeys.items: [jsonEncode(_cartEntry(price: 100))],
      });
      final api = _CommerceApi()
        ..product = catalogProduct(
          price: 100,
          discountPercent: 25,
          finalPrice: 75,
        );
      final bloc = CartBloc(apiService: api);
      addTearDown(bloc.close);

      final ready = bloc.stream.firstWhere(
        (state) => state.status == CartStatus.ready,
      );
      bloc.add(const CartStarted());
      final state = await ready;

      expect(api.productReadCalls, 1);
      expect(state.items.single.price, 75);
      expect(state.subtotal, 75);

      // The refreshed value is written back, so storage and display agree.
      final prefs = await SharedPreferences.getInstance();
      final stored =
          jsonDecode(prefs.getStringList(CartStorageKeys.items)!.single)
              as Map<String, dynamic>;
      expect(stored['price'], 75);
    });

    test('a line the server reports as sold out blocks checkout', () async {
      SharedPreferences.setMockInitialValues({
        AuthBloc.sessionKey: true,
        AuthBloc.tokenKey: 'real-token',
        CartStorageKeys.items: [jsonEncode(_cartEntry())],
      });
      final api = _CommerceApi()..product = catalogProduct(inStock: false);
      final bloc = CartBloc(apiService: api);
      addTearDown(bloc.close);

      final ready = bloc.stream.firstWhere(
        (state) => state.status == CartStatus.ready,
      );
      bloc.add(const CartStarted());
      final loaded = await ready;
      expect(loaded.items.single.inStock, isFalse);
      expect(loaded.hasUnavailableItem, isTrue);

      final failed = bloc.stream.firstWhere(
        (state) => state.status == CartStatus.failure,
      );
      bloc.add(const CartCheckoutRequested());
      final state = await failed;

      expect(state.errorMessage, 'orders.checkoutOutOfStock');
      expect(api.createOrderCalls, 0, reason: 'no order may be attempted');
    });

    test(
      'F14/F15 - a failed checkout keeps the cart and reports why',
      () async {
        SharedPreferences.setMockInitialValues({
          AuthBloc.sessionKey: true,
          AuthBloc.tokenKey: 'real-token',
          AuthBloc.addressKey: 'عنوان التوصيل',
          CartStorageKeys.items: [jsonEncode(_cartEntry(quantity: 2))],
        });
        final api = _CommerceApi()
          ..product = catalogProduct()
          ..checkoutError = _serverRefusal('PRODUCT_OUT_OF_STOCK');
        final bloc = CartBloc(apiService: api);
        addTearDown(bloc.close);

        final ready = bloc.stream.firstWhere(
          (state) => state.status == CartStatus.ready,
        );
        bloc.add(const CartStarted());
        await ready;

        final failed = bloc.stream.firstWhere(
          (state) => state.status == CartStatus.failure,
        );
        bloc.add(const CartCheckoutRequested());
        final state = await failed;

        expect(state.errorMessage, 'orders.checkoutOutOfStock');
        expect(
          state.items,
          isNotEmpty,
          reason: 'the cart must survive a refusal',
        );

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getStringList(CartStorageKeys.items), isNotEmpty);
        // The checkout id is retained so a retry reuses the same clientOrderId
        // and any order that already succeeded returns as a duplicate.
        expect(prefs.getString(CartStorageKeys.checkoutId), isNotNull);
      },
    );

    test(
      'an unmodelled failure still fails, with the generic reason',
      () async {
        SharedPreferences.setMockInitialValues({
          AuthBloc.sessionKey: true,
          AuthBloc.tokenKey: 'real-token',
          AuthBloc.addressKey: 'عنوان التوصيل',
          CartStorageKeys.items: [jsonEncode(_cartEntry())],
        });
        final api = _CommerceApi()
          ..product = catalogProduct()
          ..checkoutError = StateError('network down');
        final bloc = CartBloc(apiService: api);
        addTearDown(bloc.close);

        final ready = bloc.stream.firstWhere(
          (state) => state.status == CartStatus.ready,
        );
        bloc.add(const CartStarted());
        await ready;

        final failed = bloc.stream.firstWhere(
          (state) => state.status == CartStatus.failure,
        );
        bloc.add(const CartCheckoutRequested());
        final state = await failed;

        expect(state.errorMessage, 'orders.checkoutError');
        expect(state.items, isNotEmpty);
      },
    );
  });

  group('storefront regression', () {
    testWidgets('F16 - the store grid shows the sale price', (tester) async {
      final api = _CommerceApi()
        ..product = catalogProduct(
          price: 100,
          discountPercent: 25,
          finalPrice: 75,
        );
      final bloc = BusinessProfileBloc(apiService: api);
      final ready = bloc.stream.firstWhere(
        (state) => state.status == BusinessProfileStatus.ready,
      );
      bloc.add(const BusinessProfileStarted(_businessId));
      await ready;
      await drainMicrotasks();

      await pumpLocalized(
        tester,
        BusinessProfilePage(
          business: const HomeBusiness(
            id: _businessId,
            name: 'متجر',
            category: 'فئة',
            products: [],
            rating: 0,
            colorValue: 0xffdeeef8,
          ),
          onNavChanged: (_) {},
          bloc: bloc,
        ),
      );
      await tester.tap(find.text('المنتجات'));
      await settleFrames(tester);

      expect(find.text('₪ 75'), findsOneWidget);
      expect(find.text('₪ 100'), findsOneWidget);
    });

    testWidgets('F19 - merchant preview stays read only', (tester) async {
      final api = _CommerceApi()
        ..product = catalogProduct(
          price: 100,
          discountPercent: 25,
          finalPrice: 75,
        );
      final bloc = BusinessProfileBloc(
        apiService: api,
        viewMode: BusinessProfileViewMode.merchantPreview,
      );
      final ready = bloc.stream.firstWhere(
        (state) => state.status == BusinessProfileStatus.ready,
      );
      bloc.add(const BusinessProfileStarted(_businessId));
      await ready;
      await drainMicrotasks();

      await pumpLocalized(
        tester,
        BusinessProfilePage(
          business: const HomeBusiness(
            id: _businessId,
            name: 'متجر',
            category: 'فئة',
            products: [],
            rating: 0,
            colorValue: 0xffdeeef8,
          ),
          onNavChanged: (_) {},
          viewMode: BusinessProfileViewMode.merchantPreview,
          bloc: bloc,
        ),
      );
      await tester.tap(find.text('المنتجات'));
      await settleFrames(tester);

      // The same public sale price a customer sees...
      expect(find.text('₪ 75'), findsOneWidget);
      // ...with the cart action still inert, and no protected read issued.
      final cartButton = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('أضف إلى السلة'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(cartButton.onPressed, isNull);
      expect(api.calls.where((call) => call.contains('/favorites')), isEmpty);
    });
  });
}
