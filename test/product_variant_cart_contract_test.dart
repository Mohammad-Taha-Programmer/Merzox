import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/cart/bloc/cart_bloc.dart';
import 'package:merzox/features/cart/bloc/cart_event.dart';
import 'package:merzox/features/cart/bloc/cart_state.dart';
import 'package:merzox/features/cart/cart_storage_keys.dart';
import 'package:merzox/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_test_fixtures.dart';

const _businessId = '64b000000000000000000001';
const _productId = '64c000000000000000000001';
const _variantA = '64d000000000000000000001';
const _variantB = '64d000000000000000000002';

class _VariantCartApi extends ApiService {
  BusinessProductApiModel product;
  int createOrderCalls = 0;
  List<OrderItemRequest> submittedItems = const [];

  _VariantCartApi(this.product);

  @override
  Future<BusinessProductApiModel> businessProduct({
    required String businessId,
    required String productId,
  }) async {
    return product;
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

    throw StateError('captured checkout request');
  }
}

Map<String, dynamic> _variantCartLine({
  String variantId = _variantA,
  String variantLabel = 'Old label',
  double price = 1,
}) {
  return <String, dynamic>{
    'businessId': _businessId,
    'productId': _productId,
    'variantId': variantId,
    'variantLabel': variantLabel,
    'name': 'Variant product',
    'price': price,
    'imageUrl': '',
    'quantity': 1,
  };
}

Map<String, dynamic> _simpleCartLine({double price = 25}) {
  return <String, dynamic>{
    'businessId': _businessId,
    'productId': _productId,
    'name': 'Simple product',
    'price': price,
    'imageUrl': '',
    'quantity': 1,
  };
}

BusinessProductApiModel _variantProduct({
  String variantId = _variantA,
  String label = 'Black / M',
  double variantPrice = 120,
  double variantFinalPrice = 108,
  bool variantInStock = true,
}) {
  return catalogProduct(
    id: _productId,
    name: 'Variant product',
    price: 100,
    discountPercent: 10,
    finalPrice: 90,
    inStock: variantInStock,
    hasVariants: true,
    variants: [
      catalogVariant(
        id: variantId,
        label: label,
        price: variantPrice,
        finalPrice: variantFinalPrice,
        inStock: variantInStock,
      ),
    ],
    minPrice: variantPrice,
    maxPrice: variantPrice,
    minFinalPrice: variantFinalPrice,
    maxFinalPrice: variantFinalPrice,
  );
}

Future<CartState> _startCart(CartBloc bloc) async {
  final ready = bloc.stream.firstWhere(
    (state) => state.status == CartStatus.ready,
  );

  bloc.add(const CartStarted());

  return ready;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('public variant contract', () {
    test(
      'server variant identities and price ranges parse without private stock',
      () {
        final product = BusinessProductApiModel.fromJson(
          catalogProductJson(
            price: 100,
            discountPercent: 10,
            finalPrice: 90,
            inStock: true,
            hasVariants: true,
            variants: [
              catalogVariantJson(
                id: _variantA,
                label: 'Black / M',
                price: 120,
                finalPrice: 108,
                inStock: true,
              ),
              catalogVariantJson(
                id: _variantB,
                label: 'White / M',
                price: 100,
                finalPrice: 90,
                inStock: false,
              ),
            ],
            minPrice: 100,
            maxPrice: 120,
            minFinalPrice: 90,
            maxFinalPrice: 108,
          ),
        );

        expect(product.hasVariants, isTrue);
        expect(product.variants, hasLength(2));
        expect(product.variants.first.id, _variantA);
        expect(product.variants.first.label, 'Black / M');
        expect(product.variants.first.finalPrice, 108);
        expect(product.variants.first.inStock, isTrue);

        expect(product.minPrice, 100);
        expect(product.maxPrice, 120);
        expect(product.minFinalPrice, 90);
        expect(product.maxFinalPrice, 108);
        expect(product.displayPrice, 90);
        expect(product.hasPriceRange, isTrue);
      },
    );

    test('malformed variant summary fails closed', () {
      final broken = catalogProductJson(
        price: 100,
        discountPercent: 10,
        finalPrice: 90,
        inStock: true,
        hasVariants: true,
        variants: [
          catalogVariantJson(
            id: _variantA,
            label: 'Black / M',
            price: 120,
            finalPrice: 108,
            inStock: true,
          ),
        ],
        minPrice: 120,
        maxPrice: 120,
        minFinalPrice: 108,
        maxFinalPrice: 108,
      );

      broken['maxFinalPrice'] = 999;

      expect(
        () => BusinessProductApiModel.fromJson(broken),
        throwsA(isA<ApiContractException>()),
      );
    });

    test('variant mode with no active variants is explicitly unavailable', () {
      final product = BusinessProductApiModel.fromJson(
        catalogProductJson(
          price: 100,
          finalPrice: 100,
          inStock: false,
          hasVariants: true,
          variants: const [],
        ),
      );

      expect(product.hasVariants, isTrue);
      expect(product.variants, isEmpty);
      expect(product.inStock, isFalse);
      expect(product.minPrice, isNull);
      expect(product.maxPrice, isNull);
      expect(product.minFinalPrice, isNull);
      expect(product.maxFinalPrice, isNull);
    });
  });

  group('checkout request identity', () {
    test('simple item preserves the historical request shape', () {
      expect(
        const OrderItemRequest(productId: _productId, quantity: 2).toJson(),
        <String, dynamic>{'productId': _productId, 'quantity': 2},
      );
    });

    test('variant request sends identity but no display/commercial truth', () {
      final json = const OrderItemRequest(
        productId: _productId,
        variantId: _variantA,
        quantity: 2,
      ).toJson();

      expect(json, <String, dynamic>{
        'productId': _productId,
        'variantId': _variantA,
        'quantity': 2,
      });

      expect(json.containsKey('variant'), isFalse);
      expect(json.containsKey('variantLabel'), isFalse);
      expect(json.containsKey('price'), isFalse);
      expect(json.containsKey('stockQuantity'), isFalse);
    });
  });

  group('cart sellable identity', () {
    test(
      'exact selected variant is revalidated and forwarded to checkout',
      () async {
        SharedPreferences.setMockInitialValues({
          AuthBloc.sessionKey: true,
          AuthBloc.tokenKey: 'customer-token',
          AuthBloc.userTypeKey: 'normal',
          CartStorageKeys.items: [
            jsonEncode(
              _variantCartLine(variantLabel: 'Old Black label', price: 1),
            ),
          ],
        });

        final api = _VariantCartApi(_variantProduct());
        final bloc = CartBloc(apiService: api);
        addTearDown(bloc.close);

        final ready = await _startCart(bloc);

        expect(ready.items, hasLength(1));

        final item = ready.items.single;

        expect(item.productId, _productId);
        expect(item.variantId, _variantA);
        expect(item.variantLabel, 'Black / M');
        expect(item.price, 108);
        expect(item.inStock, isTrue);

        final prefs = await SharedPreferences.getInstance();
        final stored =
            jsonDecode(prefs.getStringList(CartStorageKeys.items)!.single)
                as Map<String, dynamic>;

        expect(stored['variantId'], _variantA);
        expect(stored['variantLabel'], 'Black / M');
        expect(stored['price'], 108);
        expect(stored.containsKey('variant'), isFalse);

        final failed = bloc.stream.firstWhere(
          (state) => state.status == CartStatus.failure,
        );

        bloc.add(const CartCheckoutRequested());
        await failed;

        expect(api.createOrderCalls, 1);
        expect(api.submittedItems, hasLength(1));
        expect(api.submittedItems.single.toJson(), <String, dynamic>{
          'productId': _productId,
          'variantId': _variantA,
          'quantity': 1,
        });
      },
    );

    test(
      'missing selected variant is unavailable and never substituted',
      () async {
        SharedPreferences.setMockInitialValues({
          AuthBloc.sessionKey: true,
          AuthBloc.tokenKey: 'customer-token',
          AuthBloc.userTypeKey: 'normal',
          CartStorageKeys.items: [
            jsonEncode(
              _variantCartLine(
                variantId: _variantA,
                variantLabel: 'Removed variant',
                price: 77,
              ),
            ),
          ],
        });

        final api = _VariantCartApi(
          _variantProduct(
            variantId: _variantB,
            label: 'Different sibling',
            variantPrice: 200,
            variantFinalPrice: 180,
          ),
        );

        final bloc = CartBloc(apiService: api);
        addTearDown(bloc.close);

        final ready = await _startCart(bloc);
        final item = ready.items.single;

        expect(item.variantId, _variantA);
        expect(item.variantLabel, 'Removed variant');
        expect(item.price, 77);
        expect(item.inStock, isFalse);
        expect(ready.hasUnavailableItem, isTrue);

        final failed = bloc.stream.firstWhere(
          (state) => state.status == CartStatus.failure,
        );

        bloc.add(const CartCheckoutRequested());

        final checkoutState = await failed;

        expect(checkoutState.errorMessage, 'orders.checkoutOutOfStock');
        expect(api.createOrderCalls, 0);
      },
    );

    test(
      'simple cart line cannot auto-select when product becomes variant-mode',
      () async {
        SharedPreferences.setMockInitialValues({
          CartStorageKeys.items: [jsonEncode(_simpleCartLine())],
        });

        final api = _VariantCartApi(_variantProduct());
        final bloc = CartBloc(apiService: api);
        addTearDown(bloc.close);

        final ready = await _startCart(bloc);
        final item = ready.items.single;

        expect(item.variantId, isNull);
        expect(item.variantLabel, isEmpty);
        expect(item.inStock, isFalse);
        expect(item.price, 25);
      },
    );

    test('malformed stored variant identity is discarded', () async {
      SharedPreferences.setMockInitialValues({
        CartStorageKeys.items: [
          jsonEncode(_variantCartLine(variantId: 'not-a-mongo-id')),
        ],
      });

      final api = _VariantCartApi(_variantProduct());
      final bloc = CartBloc(apiService: api);
      addTearDown(bloc.close);

      final ready = await _startCart(bloc);

      expect(ready.items, isEmpty);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(CartStorageKeys.items), isEmpty);
    });
  });
}
