import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_bloc.dart';
import 'package:merzox/features/business_profile/business_profile_view_mode.dart';
import 'package:merzox/features/business_profile/pages/business_profile_page.dart';
import 'package:merzox/features/home/presentation/bloc/home_state_.dart';
import 'package:merzox/features/product_details/bloc/product_details_bloc.dart';
import 'package:merzox/features/product_details/bloc/product_details_event.dart';
import 'package:merzox/features/product_details/bloc/product_details_state.dart';
import 'package:merzox/features/product_details/pages/product_details_page.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/services/review_eligibility_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_test_fixtures.dart';
import 'localization_test_harness.dart';

const _business = HomeBusiness(
  id: '64b000000000000000000001',
  name: 'Test business',
  category: 'Test category',
  products: [],
  rating: 0,
  colorValue: 0xffdeeef8,
);

void _expectDirection(
  WidgetTester tester,
  Finder finder,
  TextDirection expected,
) {
  expect(finder, findsOneWidget);
  expect(Directionality.of(tester.element(finder)), expected);
}

class _FakeProductDetailsApi extends ApiService {
  final BusinessProductApiModel product;

  _FakeProductDetailsApi(this.product);

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
}

class _EligibleReviewGateway implements ReviewEligibilityGateway {
  @override
  Future<ReviewEligibilityDecision> businessEligibility({
    required String token,
    required String businessId,
  }) async {
    return const ReviewEligibilityDecision(eligible: true, reason: null);
  }

  @override
  Future<ReviewEligibilityDecision> productEligibility({
    required String token,
    required String businessId,
    required String productId,
  }) async {
    return const ReviewEligibilityDecision(eligible: true, reason: null);
  }
}

Future<void> _pumpBusinessProfile(
  WidgetTester tester, {
  required TextDirection direction,
}) async {
  // Rendering-only seam. No BusinessProfileStarted event is dispatched,
  // therefore this widget test performs no storefront API request.
  final bloc = BusinessProfileBloc(viewMode: BusinessProfileViewMode.customer);

  await pumpLocalized(
    tester,
    BusinessProfilePage(business: _business, onNavChanged: (_) {}, bloc: bloc),
    textDirection: direction,
  );
}

Future<(ProductDetailsBloc, BusinessProductApiModel)>
_readyProductBloc() async {
  final product = catalogProduct(
    name: 'Test product',
    description: 'Test description',
  );

  final bloc = ProductDetailsBloc(
    apiService: _FakeProductDetailsApi(product),
    reviewEligibilityGateway: _EligibleReviewGateway(),
  );

  final ready = bloc.stream.firstWhere(
    (state) =>
        state.detailsStatus == ProductDetailsSectionStatus.ready &&
        state.reviewsStatus == ProductDetailsSectionStatus.ready,
  );

  // This uses only the fake in-memory API above. No external request can leave
  // this localization test.
  bloc.add(
    ProductDetailsStarted(businessId: _business.id, initialProduct: product),
  );

  await ready;

  return (bloc, product);
}

Future<ProductDetailsBloc> _pumpProductDetails(
  WidgetTester tester, {
  required TextDirection direction,
}) async {
  final (bloc, product) = await _readyProductBloc();

  await pumpLocalized(
    tester,
    ProductDetailsPage(business: _business, product: product, bloc: bloc),
    textDirection: direction,
  );

  return bloc;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final language in ['ar', 'en']) {
    group('GAP-015D $language localization', () {
      setUpAll(() async {
        await loadAppTranslations(languageCode: language);
      });

      setUp(() {
        // Authenticated normal customer so opening the review tab exercises
        // the localized review composer through the fake eligibility gateway.
        SharedPreferences.setMockInitialValues({
          AuthBloc.sessionKey: true,
          AuthBloc.tokenKey: 'customer-token',
          AuthBloc.userTypeKey: 'normal',
        });
      });

      testWidgets('Business Profile renders localized storefront shell', (
        tester,
      ) async {
        final isArabic = language == 'ar';
        final direction = isArabic ? TextDirection.rtl : TextDirection.ltr;

        final followers = isArabic ? '0 متابع' : '0 followers';
        final productsCount = isArabic ? '0 منتج' : '0 products';
        final about = isArabic ? 'عن المتجر' : 'About';
        final products = isArabic ? 'المنتجات' : 'Products';
        final reviews = isArabic ? 'التقييمات' : 'Reviews';

        await _pumpBusinessProfile(tester, direction: direction);

        expect(find.text(followers), findsOneWidget);
        expect(find.text(productsCount), findsOneWidget);
        expect(find.text(about), findsOneWidget);
        expect(find.text(products), findsOneWidget);
        expect(find.text(reviews), findsOneWidget);

        _expectDirection(tester, find.text(followers), direction);
        _expectDirection(tester, find.text(about), direction);

        expect(
          find.byIcon(
            isArabic ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
          ),
          findsOneWidget,
        );
      });

      testWidgets(
        'Product Details renders localized description and logical actions',
        (tester) async {
          final isArabic = language == 'ar';
          final direction = isArabic ? TextDirection.rtl : TextDirection.ltr;

          final description = isArabic ? 'الوصف' : 'Description';
          final reviews = isArabic ? 'التقييمات' : 'Reviews';
          final quantity = isArabic ? 'الكمية' : 'Quantity';
          final seller = isArabic ? 'تفاصيل البائع' : 'Seller details';
          final addToCart = isArabic ? 'أضف إلى السلة' : 'Add to cart';
          final buyNow = isArabic ? 'شراء الآن' : 'Buy now';

          await _pumpProductDetails(tester, direction: direction);

          expect(find.text('Test product'), findsOneWidget);
          expect(find.text(description), findsOneWidget);
          expect(find.text(reviews), findsOneWidget);
          expect(find.text(quantity), findsOneWidget);
          expect(find.text(seller), findsOneWidget);
          expect(find.text(addToCart), findsOneWidget);
          expect(find.text(buyNow), findsOneWidget);

          _expectDirection(tester, find.text(description), direction);
          _expectDirection(tester, find.text(quantity), direction);
          _expectDirection(tester, find.text(seller), direction);

          final productName = tester.widget<Text>(find.text('Test product'));
          expect(productName.textAlign, TextAlign.start);

          final price = tester.widget<Text>(find.text('₪ 25'));
          expect(price.textDirection, TextDirection.ltr);

          final addX = tester.getCenter(find.text(addToCart)).dx;
          final buyX = tester.getCenter(find.text(buyNow)).dx;

          if (isArabic) {
            expect(addX, greaterThan(buyX));
          } else {
            expect(addX, lessThan(buyX));
          }
        },
      );

      testWidgets(
        'Product Details renders localized eligible review composer',
        (tester) async {
          final isArabic = language == 'ar';
          final direction = isArabic ? TextDirection.rtl : TextDirection.ltr;

          final reviews = isArabic ? 'التقييمات' : 'Reviews';
          final hint = isArabic
              ? 'قم بكتابة تقييمك للمنتج الذي قمت بشرائه هنا'
              : 'Write your review of the product you purchased here';
          final publish = isArabic ? 'نشر' : 'Publish';
          final count = isArabic ? '(0 تقييم)' : '(0 reviews)';
          final allReviews = isArabic ? 'كل التقييمات' : 'All reviews';

          await _pumpProductDetails(tester, direction: direction);

          await tester.tap(find.text(reviews));
          await settleFrames(tester);

          expect(find.text(hint), findsOneWidget);
          expect(find.text(publish), findsOneWidget);
          expect(find.text(count), findsOneWidget);
          expect(find.text(allReviews), findsOneWidget);

          _expectDirection(tester, find.text(hint), direction);
          _expectDirection(tester, find.text(allReviews), direction);

          final field = tester.widget<TextField>(find.byType(TextField).first);
          expect(field.textAlign, TextAlign.start);
        },
      );
    });
  }
}
