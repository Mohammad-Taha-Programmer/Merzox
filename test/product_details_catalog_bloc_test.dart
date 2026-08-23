import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/cart/cart_storage_keys.dart';
import 'package:merzox/features/product_details/bloc/product_details_bloc.dart';
import 'package:merzox/features/product_details/bloc/product_details_event.dart';
import 'package:merzox/features/product_details/bloc/product_details_state.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/services/product_share_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_test_fixtures.dart';

class _FakeProductDetailsApi extends ApiService {
  final bool failReviews;

  _FakeProductDetailsApi({this.failReviews = false});

  @override
  Future<BusinessProductApiModel> businessProduct({
    required String businessId,
    required String productId,
  }) async {
    return catalogProduct(id: productId);
  }

  @override
  Future<List<BusinessReviewApiModel>> productReviews({
    required String businessId,
    required String productId,
  }) async {
    if (failReviews) throw StateError('reviews offline');
    return const [];
  }
}

class _FakeProductShareGateway implements ProductShareGateway {
  ProductShareOutcome outcome = ProductShareOutcome.selected;
  Object? error;

  String? productName;
  String? businessName;
  double? displayPrice;
  String? languageCode;
  Rect? sharePositionOrigin;
  int calls = 0;

  @override
  Future<ProductShareOutcome> shareProduct({
    required String productName,
    required String businessName,
    required double displayPrice,
    required String languageCode,
    Rect? sharePositionOrigin,
  }) async {
    calls += 1;
    this.productName = productName;
    this.businessName = businessName;
    this.displayPrice = displayPrice;
    this.languageCode = languageCode;
    this.sharePositionOrigin = sharePositionOrigin;

    if (error != null) {
      throw error!;
    }

    return outcome;
  }
}

Future<void> _startReady(ProductDetailsBloc bloc) async {
  final ready = bloc.stream.firstWhere(
    (state) =>
        state.detailsStatus == ProductDetailsSectionStatus.ready &&
        state.reviewsStatus == ProductDetailsSectionStatus.ready,
  );

  bloc.add(
    ProductDetailsStarted(
      businessId: '64b000000000000000000001',
      initialProduct: catalogProduct(),
    ),
  );

  await ready;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'empty product reviews and description remain empty without synthetic data',
    () async {
      final product = catalogProduct(description: '');
      final bloc = ProductDetailsBloc(apiService: _FakeProductDetailsApi());
      addTearDown(bloc.close);

      final stateFuture = bloc.stream.firstWhere(
        (state) =>
            state.detailsStatus == ProductDetailsSectionStatus.ready &&
            state.reviewsStatus == ProductDetailsSectionStatus.ready,
      );
      bloc.add(
        ProductDetailsStarted(
          businessId: '64b000000000000000000001',
          initialProduct: product,
        ),
      );
      final state = await stateFuture;

      expect(state.product?.description, isEmpty);
      expect(state.reviews, isEmpty);
    },
  );

  test(
    'product review failures stay failures with no fallback reviews',
    () async {
      final bloc = ProductDetailsBloc(
        apiService: _FakeProductDetailsApi(failReviews: true),
      );
      addTearDown(bloc.close);

      final stateFuture = bloc.stream.firstWhere(
        (state) =>
            state.detailsStatus == ProductDetailsSectionStatus.ready &&
            state.reviewsStatus == ProductDetailsSectionStatus.failure,
      );
      bloc.add(
        ProductDetailsStarted(
          businessId: '64b000000000000000000001',
          initialProduct: catalogProduct(),
        ),
      );
      final state = await stateFuture;

      expect(state.reviews, isEmpty);
      expect(state.reviewsError, isNotEmpty);
    },
  );

  test('adding a real product stores no synthetic degree or variant', () async {
    SharedPreferences.setMockInitialValues({
      AuthBloc.sessionKey: true,
      AuthBloc.tokenKey: 'customer-token',
      AuthBloc.userTypeKey: 'normal',
    });
    final bloc = ProductDetailsBloc(apiService: _FakeProductDetailsApi());
    addTearDown(bloc.close);

    final readyFuture = bloc.stream.firstWhere(
      (state) =>
          state.detailsStatus == ProductDetailsSectionStatus.ready &&
          state.reviewsStatus == ProductDetailsSectionStatus.ready,
    );
    bloc.add(
      ProductDetailsStarted(
        businessId: '64b000000000000000000001',
        initialProduct: catalogProduct(),
      ),
    );
    await readyFuture;

    final actionFuture = bloc.stream.firstWhere(
      (state) => state.status == ProductDetailsStatus.action,
    );
    bloc.add(const ProductDetailsAddToCartPressed());
    await actionFuture;

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(CartStorageKeys.items)!;
    final item = jsonDecode(stored.single) as Map<String, dynamic>;
    expect(item['businessId'], '64b000000000000000000001');
    expect(item['productId'], '64c000000000000000000001');
    expect(item.containsKey('degree'), isFalse);
    expect(item.containsKey('variant'), isFalse);

    expect(
      const OrderItemRequest(
        productId: '64c000000000000000000001',
        quantity: 1,
      ).toJson().containsKey('variant'),
      isFalse,
    );
  });

  test(
    'product sharing needs no auth session and uses visible product truth',
    () async {
      final share = _FakeProductShareGateway();
      final bloc = ProductDetailsBloc(
        apiService: _FakeProductDetailsApi(),
        productShareGateway: share,
      );
      addTearDown(bloc.close);

      await _startReady(bloc);

      final completed = bloc.stream.firstWhere(
        (state) => state.message == 'catalog.productShareOpened',
      );

      const origin = Rect.fromLTWH(10, 20, 30, 40);

      bloc.add(
        const ProductDetailsShareRequested(
          businessName: 'Test business',
          languageCode: 'en',
          sharePositionOrigin: origin,
        ),
      );

      final state = await completed;

      expect(state.status, ProductDetailsStatus.ready);
      expect(share.calls, 1);
      expect(share.productName, 'Test product');
      expect(share.businessName, 'Test business');
      expect(share.displayPrice, 25);
      expect(share.languageCode, 'en');
      expect(share.sharePositionOrigin, origin);
    },
  );

  test('dismissing product share is quiet and returns to ready', () async {
    final share = _FakeProductShareGateway()
      ..outcome = ProductShareOutcome.dismissed;

    final bloc = ProductDetailsBloc(
      apiService: _FakeProductDetailsApi(),
      productShareGateway: share,
    );
    addTearDown(bloc.close);

    await _startReady(bloc);

    final completed = bloc.stream.firstWhere(
      (state) => state.status == ProductDetailsStatus.ready && share.calls == 1,
    );

    bloc.add(
      const ProductDetailsShareRequested(
        businessName: 'Test business',
        languageCode: 'en',
      ),
    );

    final state = await completed;

    expect(state.message, isNull);
    expect(state.errorMessage, isNull);
  });

  test('product share failure becomes a localized stable error', () async {
    final share = _FakeProductShareGateway()
      ..error = StateError('platform share failed');

    final bloc = ProductDetailsBloc(
      apiService: _FakeProductDetailsApi(),
      productShareGateway: share,
    );
    addTearDown(bloc.close);

    await _startReady(bloc);

    final failed = bloc.stream.firstWhere(
      (state) => state.errorMessage == 'catalog.productShareError',
    );

    bloc.add(
      const ProductDetailsShareRequested(
        businessName: 'Test business',
        languageCode: 'ar',
      ),
    );

    final state = await failed;

    expect(state.status, ProductDetailsStatus.failure);
    expect(state.message, isNull);
    expect(share.calls, 1);
  });
}
