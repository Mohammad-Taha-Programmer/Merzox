import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/home/presentation/bloc/home_state_.dart';
import 'package:merzox/features/product_details/bloc/product_details_bloc.dart';
import 'package:merzox/features/product_details/bloc/product_details_event.dart';
import 'package:merzox/features/product_details/bloc/product_details_state.dart';
import 'package:merzox/features/product_details/pages/product_details_page.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/services/product_share_service.dart';

import 'catalog_test_fixtures.dart';
import 'localization_test_harness.dart';

class _ProductSharePageApi extends ApiService {
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
    return const [];
  }
}

class _PageShareGateway implements ProductShareGateway {
  int calls = 0;
  String? productName;
  String? businessName;
  Rect? origin;

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
    origin = sharePositionOrigin;

    return ProductShareOutcome.selected;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadAppTranslations);

  testWidgets('product share icon dispatches real sharing without auth gate', (
    tester,
  ) async {
    final share = _PageShareGateway();
    final product = catalogProduct();

    final bloc = ProductDetailsBloc(
      apiService: _ProductSharePageApi(),
      productShareGateway: share,
    );

    // ProductDetailsPage receives this bloc through BlocProvider(create: ...),
    // so the widget tree owns and closes it. Registering bloc.close again in
    // addTearDown would create a second owner for the same lifecycle.
    final ready = bloc.stream.firstWhere(
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

    await ready;

    await pumpLocalized(
      tester,
      ProductDetailsPage(
        business: const HomeBusiness(
          id: '64b000000000000000000001',
          name: 'Test business',
          category: 'Test category',
          products: [],
          rating: 0,
          colorValue: 0xffdeeef8,
        ),
        product: product,
        bloc: bloc,
      ),
    );

    expect(find.byIcon(Icons.share_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.share_outlined));
    await settleFrames(tester);

    expect(share.calls, 1);
    expect(share.productName, 'Test product');
    expect(share.businessName, 'Test business');

    // share_plus requires this on iPad. The page supplies it from the actual
    // rendered share button rather than inventing a screen rectangle.
    expect(share.origin, isNotNull);
    expect(share.origin!.width, greaterThan(0));
    expect(share.origin!.height, greaterThan(0));
  });
}
