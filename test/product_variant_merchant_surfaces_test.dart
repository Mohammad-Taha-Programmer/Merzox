import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/features/cart/cart_storage_keys.dart';
import 'package:merzox/features/favorites/bloc/favorites_bloc.dart';
import 'package:merzox/features/favorites/bloc/favorites_event.dart';
import 'package:merzox/features/favorites/bloc/favorites_state.dart';
import 'package:merzox/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_session_fixtures.dart';
import 'catalog_test_fixtures.dart';

const _businessId = '64b000000000000000000001';
const _productId = '64c000000000000000000001';
const _variantId = '64d000000000000000000001';

class _FavoritesApi extends ApiService {
  final FavoriteProductApiModel favorite;

  _FavoritesApi(this.favorite);

  @override
  Future<FavoriteProductListApiResponse> favoriteProducts({
    required String token,
    int page = 1,
    int limit = 20,
  }) async {
    return FavoriteProductListApiResponse(
      products: [favorite],
      page: page,
      total: 1,
      hasMore: false,
    );
  }
}

FavoriteProductApiModel _favorite(BusinessProductApiModel product) {
  return FavoriteProductApiModel(
    business: SearchBusinessApiModel.fromJson(const {
      'id': _businessId,
      'name': 'Variant Store',
    }),
    product: product,
    favoritedAt: null,
  );
}

BusinessProductApiModel _variantProduct() {
  return catalogProduct(
    id: _productId,
    name: 'Variant product',
    price: 100,
    finalPrice: 100,
    inStock: true,
    hasVariants: true,
    variants: [
      catalogVariant(
        id: _variantId,
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
}

Future<FavoritesBloc> _loadedProductsBloc(
  FavoriteProductApiModel favorite,
) async {
  final bloc = FavoritesBloc(apiService: _FavoritesApi(favorite));

  final loaded = bloc.stream.firstWhere(
    (state) => state.productsLoaded && state.status == FavoritesStatus.ready,
  );

  bloc.add(const FavoritesTabChanged(FavoritesTab.products));

  await loaded;

  return bloc;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(useAuthenticatedSession);

  group('merchant variant models', () {
    test(
      'owner payload keeps stable variant identity and private inventory',
      () {
        final product = OwnerProduct.fromJson(const {
          'id': _productId,
          'name': 'Shirt',
          'price': 100,
          'variants': [
            {
              'id': _variantId,
              'label': 'Black / M',
              'price': 120,
              'finalPrice': 108,
              'priceOverride': 120,
              'costPrice': 50,
              'stockQuantity': 3,
              'unlimitedStock': false,
              'isActive': true,
              'inStock': true,
            },
          ],
        });

        expect(product.hasVariants, isTrue);
        expect(product.variants, hasLength(1));

        final variant = product.variants.single;

        expect(variant.id, _variantId);
        expect(variant.label, 'Black / M');
        expect(variant.priceOverride, 120);
        expect(variant.costPrice, 50);
        expect(variant.stockQuantity, 3);
        expect(variant.unlimitedStock, isFalse);
        expect(variant.price, 120);
        expect(variant.finalPrice, 108);
        expect(variant.inStock, isTrue);
      },
    );

    test(
      'existing variant draft preserves id while a new variant invents none',
      () {
        const ownerVariant = OwnerProductVariant(
          id: _variantId,
          label: 'Black / M',
          price: 120,
          finalPrice: 108,
          inStock: true,
          priceOverride: 120,
          costPrice: 50,
          stockQuantity: 3,
          unlimitedStock: false,
        );

        final existing = OwnerProductVariantDraft.fromOwner(
          ownerVariant,
        ).toJson();

        expect(existing['id'], _variantId);
        expect(existing['label'], 'Black / M');
        expect(existing['stockQuantity'], 3);

        const newDraft = OwnerProductVariantDraft(
          label: 'White / L',
          priceOverride: null,
          costPrice: null,
          stockQuantity: 0,
          unlimitedStock: true,
          isActive: true,
        );

        final created = newDraft.toJson();

        expect(created.containsKey('id'), isFalse);
        expect(created.containsKey('stockQuantity'), isFalse);
        expect(created['priceOverride'], isNull);
      },
    );

    test('explicit null clears override without dropping existing id', () {
      const draft = OwnerProductVariantDraft(
        id: _variantId,
        label: 'Black / M',
        priceOverride: null,
        costPrice: null,
        stockQuantity: 2,
        unlimitedStock: false,
        isActive: true,
      );

      final json = draft.toJson();

      expect(json['id'], _variantId);
      expect(json.containsKey('priceOverride'), isTrue);
      expect(json['priceOverride'], isNull);
      expect(json.containsKey('costPrice'), isTrue);
      expect(json['costPrice'], isNull);
      expect(json['stockQuantity'], 2);
    });
  });

  test(
    'merchant order item keeps variant id and purchase-time label snapshot',
    () {
      final item = OwnerOrderItem.fromJson(const {
        'productId': _productId,
        'variantId': _variantId,
        'name': 'Shirt',
        'variant': 'Black / M',
        'unitPrice': 108,
        'quantity': 2,
      });

      expect(item.productId, _productId);
      expect(item.variantId, _variantId);
      expect(item.variant, 'Black / M');
      expect(item.lineTotal, 216);
    },
  );

  group('favorites variant fence', () {
    test('variant favorite cannot directly create a cart line', () async {
      final bloc = await _loadedProductsBloc(_favorite(_variantProduct()));

      final refused = bloc.stream.firstWhere(
        (state) => state.errorMessage == 'catalog.selectVariant',
      );

      bloc.add(
        const FavoriteProductAddedToCart(
          businessId: _businessId,
          productId: _productId,
        ),
      );

      await refused;

      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getStringList(CartStorageKeys.items), isNull);

      await bloc.close();
    });

    test('simple favorite retains direct-cart compatibility', () async {
      final product = catalogProduct(
        id: _productId,
        name: 'Simple product',
        price: 25,
        finalPrice: 25,
        inStock: true,
      );

      final bloc = await _loadedProductsBloc(_favorite(product));

      final added = bloc.stream.firstWhere(
        (state) => state.messageCode == 'favorites.addedToCart',
      );

      bloc.add(
        const FavoriteProductAddedToCart(
          businessId: _businessId,
          productId: _productId,
        ),
      );

      await added;

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(CartStorageKeys.items);

      expect(stored, hasLength(1));

      final line = jsonDecode(stored!.single) as Map<String, dynamic>;

      expect(line['businessId'], _businessId);
      expect(line['productId'], _productId);
      expect(line.containsKey('variantId'), isFalse);

      await bloc.close();
    });
  });
}
