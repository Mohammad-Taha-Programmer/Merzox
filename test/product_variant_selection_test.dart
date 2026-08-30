import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/cart/cart_storage_keys.dart';
import 'package:merzox/features/home/presentation/bloc/home_state_.dart';
import 'package:merzox/features/product_details/bloc/product_details_bloc.dart';
import 'package:merzox/features/product_details/bloc/product_details_event.dart';
import 'package:merzox/features/product_details/bloc/product_details_state.dart';
import 'package:merzox/features/product_details/pages/product_details_page.dart';
import 'package:merzox/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_test_fixtures.dart';
import 'localization_test_harness.dart';

const _businessId = '64b000000000000000000001';
const _productId = '64c000000000000000000001';
const _variantA = '64d000000000000000000001';
const _variantB = '64d000000000000000000002';

BusinessProductApiModel _variantProduct({
  List<BusinessProductVariantApiModel>? variants,
}) {
  final choices =
      variants ??
      [
        catalogVariant(
          id: _variantA,
          label: 'Black / M',
          price: 120,
          finalPrice: 108,
          inStock: true,
        ),
        catalogVariant(
          id: _variantB,
          label: 'White / M',
          price: 100,
          finalPrice: 90,
          inStock: true,
        ),
      ];

  final prices = choices.map((item) => item.price).toList();
  final finals = choices.map((item) => item.finalPrice).toList();

  return catalogProduct(
    id: _productId,
    name: 'Variant product',
    description: 'Variant description',
    price: 100,
    discountPercent: 10,
    finalPrice: 90,
    inStock: choices.any((item) => item.inStock),
    hasVariants: true,
    variants: choices,
    minPrice: choices.isEmpty ? null : prices.reduce((a, b) => a < b ? a : b),
    maxPrice: choices.isEmpty ? null : prices.reduce((a, b) => a > b ? a : b),
    minFinalPrice: choices.isEmpty
        ? null
        : finals.reduce((a, b) => a < b ? a : b),
    maxFinalPrice: choices.isEmpty
        ? null
        : finals.reduce((a, b) => a > b ? a : b),
  );
}

class _SelectionApi extends ApiService {
  BusinessProductApiModel product;
  int createOrderCalls = 0;
  List<OrderItemRequest> submittedItems = const [];

  _SelectionApi(this.product);

  @override
  Future<BusinessProductApiModel> businessProduct({
    required String businessId,
    required String productId,
  }) async {
    return product;
  }

  @override
  Future<List<BusinessReviewApiModel>> productReviews({
    required String businessId,
    required String productId,
  }) async {
    return const [];
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
    createOrderCalls += 1;
    submittedItems = List<OrderItemRequest>.unmodifiable(items);

    throw StateError('captured buy-now request');
  }
}

Future<ProductDetailsState> _start(
  ProductDetailsBloc bloc,
  BusinessProductApiModel product,
) async {
  final ready = bloc.stream.firstWhere(
    (state) =>
        state.detailsStatus == ProductDetailsSectionStatus.ready &&
        state.reviewsStatus == ProductDetailsSectionStatus.ready,
  );

  bloc.add(
    ProductDetailsStarted(businessId: _businessId, initialProduct: product),
  );

  return ready;
}

Future<ProductDetailsState> _select(
  ProductDetailsBloc bloc,
  String variantId,
) async {
  final selected = bloc.stream.firstWhere(
    (state) =>
        state.selectedVariantId == variantId &&
        state.status == ProductDetailsStatus.ready,
  );

  bloc.add(ProductDetailsVariantSelected(variantId));

  return selected;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadAppTranslations);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'variant product requires explicit selection before add to cart',
    () async {
      SharedPreferences.setMockInitialValues({
        AuthBloc.sessionKey: true,
        AuthBloc.tokenKey: 'customer-token',
        AuthBloc.userTypeKey: 'normal',
      });

      final product = _variantProduct();
      final api = _SelectionApi(product);
      final bloc = ProductDetailsBloc(apiService: api);
      addTearDown(bloc.close);

      final started = await _start(bloc, product);

      expect(started.selectedVariantId, isNull);
      expect(started.selectedVariant, isNull);
      expect(started.variantSelectionRequired, isTrue);

      final refused = bloc.stream.firstWhere(
        (state) => state.errorMessage == 'catalog.selectVariant',
      );

      bloc.add(const ProductDetailsAddToCartPressed());

      await refused;

      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getStringList(CartStorageKeys.items), isNull);
    },
  );

  test(
    'selected variant writes exact identity, label and server display price',
    () async {
      SharedPreferences.setMockInitialValues({
        AuthBloc.sessionKey: true,
        AuthBloc.tokenKey: 'customer-token',
        AuthBloc.userTypeKey: 'normal',
      });

      final product = _variantProduct();
      final bloc = ProductDetailsBloc(apiService: _SelectionApi(product));
      addTearDown(bloc.close);

      await _start(bloc, product);
      final selected = await _select(bloc, _variantA);

      expect(selected.selectedVariant?.label, 'Black / M');
      expect(selected.selectedVariant?.finalPrice, 108);

      final added = bloc.stream.firstWhere(
        (state) =>
            state.status == ProductDetailsStatus.action &&
            state.message == 'catalog.addedToCart',
      );

      bloc.add(const ProductDetailsAddToCartPressed());

      await added;

      final prefs = await SharedPreferences.getInstance();

      final raw = prefs.getStringList(CartStorageKeys.items)!.single;

      final stored = jsonDecode(raw) as Map<String, dynamic>;

      expect(stored['businessId'], _businessId);
      expect(stored['productId'], _productId);
      expect(stored['variantId'], _variantA);
      expect(stored['variantLabel'], 'Black / M');
      expect(stored['price'], 108);
      expect(stored['quantity'], 1);

      expect(stored.containsKey('variant'), isFalse);
      expect(stored.containsKey('unitPrice'), isFalse);
      expect(stored.containsKey('stockQuantity'), isFalse);
      expect(stored.containsKey('costPrice'), isFalse);
    },
  );

  test('buy now forwards selected variant id but no display truth', () async {
    SharedPreferences.setMockInitialValues({
      AuthBloc.sessionKey: true,
      AuthBloc.tokenKey: 'customer-token',
      AuthBloc.userTypeKey: 'normal',
    });

    final product = _variantProduct();
    final api = _SelectionApi(product);
    final bloc = ProductDetailsBloc(apiService: api);
    addTearDown(bloc.close);

    await _start(bloc, product);
    await _select(bloc, _variantB);

    final failed = bloc.stream.firstWhere(
      (state) => state.status == ProductDetailsStatus.failure,
    );

    bloc.add(const ProductDetailsBuyNowPressed());

    await failed;

    expect(api.createOrderCalls, 1);
    expect(api.submittedItems, hasLength(1));

    expect(api.submittedItems.single.toJson(), <String, dynamic>{
      'productId': _productId,
      'variantId': _variantB,
      'quantity': 1,
    });
  });

  test(
    'reload clears removed selection and never substitutes a sibling',
    () async {
      final original = _variantProduct();
      final api = _SelectionApi(original);
      final bloc = ProductDetailsBloc(apiService: api);
      addTearDown(bloc.close);

      await _start(bloc, original);
      await _select(bloc, _variantA);

      api.product = _variantProduct(
        variants: [
          catalogVariant(
            id: _variantB,
            label: 'White / M',
            price: 100,
            finalPrice: 90,
            inStock: true,
          ),
        ],
      );

      final reloaded = bloc.stream.firstWhere(
        (state) =>
            state.detailsStatus == ProductDetailsSectionStatus.ready &&
            state.product?.variants.length == 1 &&
            state.product?.variants.single.id == _variantB &&
            state.selectedVariantId == null,
      );

      bloc.add(const ProductDetailsReloadRequested());

      final state = await reloaded;

      expect(state.selectedVariant, isNull);
      expect(state.selectedVariantId, isNull);
      expect(state.variantSelectionRequired, isTrue);
    },
  );

  testWidgets('variant UI shows explicit choices and selected price', (
    tester,
  ) async {
    final product = _variantProduct();
    final bloc = ProductDetailsBloc(apiService: _SelectionApi(product));

    await _start(bloc, product);

    await pumpLocalized(
      tester,
      ProductDetailsPage(
        business: const HomeBusiness(
          id: _businessId,
          name: 'Test store',
          category: 'Retail',
          products: [],
          rating: 0,
          colorValue: 0xffdeeef8,
        ),
        product: product,
        bloc: bloc,
      ),
    );

    expect(find.text('اختر الخيار'), findsOneWidget);
    expect(find.text('Black / M'), findsOneWidget);
    expect(find.text('White / M'), findsOneWidget);

    // Before selection the bottom purchase action is replaced with truthful
    // selection guidance.
    expect(
      find.text('اختر أحد الخيارات قبل إضافة المنتج أو شرائه'),
      findsOneWidget,
    );

    await tester.tap(find.text('Black / M'));
    await settleFrames(tester);

    expect(bloc.state.selectedVariantId, _variantA);
    expect(find.text('₪ 108'), findsOneWidget);

    // Once an in-stock variant is selected, purchase actions become visible.
    expect(find.text('شراء الآن'), findsOneWidget);
    expect(find.text('أضف إلى السلة'), findsOneWidget);
  });
}
