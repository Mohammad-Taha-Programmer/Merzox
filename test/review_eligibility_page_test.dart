import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_bloc.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_event.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_state.dart';
import 'package:merzox/features/business_profile/pages/business_profile_page.dart';
import 'package:merzox/features/home/presentation/bloc/home_state_.dart';
import 'package:merzox/features/product_details/bloc/product_details_bloc.dart';
import 'package:merzox/features/product_details/bloc/product_details_event.dart';
import 'package:merzox/features/product_details/bloc/product_details_state.dart';
import 'package:merzox/features/product_details/pages/product_details_page.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/services/review_eligibility_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_session_fixtures.dart';
import 'catalog_test_fixtures.dart';
import 'localization_test_harness.dart';

const _businessId = '64b000000000000000000001';

final class _FakeEligibilityGateway implements ReviewEligibilityGateway {
  ReviewEligibilityDecision businessDecision;
  ReviewEligibilityDecision productDecision;

  int businessCalls = 0;
  int productCalls = 0;

  _FakeEligibilityGateway({
    this.businessDecision = const ReviewEligibilityDecision(
      eligible: true,
      reason: null,
    ),
    this.productDecision = const ReviewEligibilityDecision(
      eligible: true,
      reason: null,
    ),
  });

  @override
  Future<ReviewEligibilityDecision> businessEligibility({
    required String token,
    required String businessId,
  }) async {
    businessCalls += 1;
    return businessDecision;
  }

  @override
  Future<ReviewEligibilityDecision> productEligibility({
    required String token,
    required String businessId,
    required String productId,
  }) async {
    productCalls += 1;
    return productDecision;
  }
}

final class _FakeBusinessApi extends ApiService {
  @override
  Future<BusinessDetailApiModel> business({required String businessId}) async {
    return catalogBusinessDetail(id: businessId);
  }

  @override
  Future<List<BusinessProductApiModel>> businessProducts({
    required String businessId,
    required String classification,
  }) async {
    return const [];
  }

  @override
  Future<List<BusinessReviewApiModel>> businessReviews({
    required String businessId,
  }) async {
    return const [];
  }

  @override
  Future<FavoriteStatusApiResponse> favoriteStatus({
    required String token,
    required String businessId,
  }) async {
    return const FavoriteStatusApiResponse(
      businessFavorited: false,
      productIds: <String>{},
    );
  }
}

final class _FakeProductApi extends ApiService {
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

HomeBusiness _businessSeed() {
  return HomeBusiness.fromApi(catalogBusiness());
}

Future<BusinessProfileBloc> _startBusinessBloc(
  ReviewEligibilityGateway gateway,
) async {
  final bloc = BusinessProfileBloc(
    apiService: _FakeBusinessApi(),
    reviewEligibilityGateway: gateway,
  );

  final ready = bloc.stream.firstWhere(
    (state) => state.status == BusinessProfileStatus.ready,
  );

  bloc.add(const BusinessProfileStarted(_businessId));
  await ready;

  return bloc;
}

Future<ProductDetailsBloc> _startProductBloc(
  ReviewEligibilityGateway gateway,
) async {
  final bloc = ProductDetailsBloc(
    apiService: _FakeProductApi(),
    reviewEligibilityGateway: gateway,
  );

  final ready = bloc.stream.firstWhere(
    (state) =>
        state.detailsStatus == ProductDetailsSectionStatus.ready &&
        state.reviewsStatus == ProductDetailsSectionStatus.ready,
  );

  bloc.add(
    ProductDetailsStarted(
      businessId: _businessId,
      initialProduct: catalogProduct(),
    ),
  );

  await ready;

  return bloc;
}

Future<void> _openBusinessReviews(
  WidgetTester tester,
  ReviewEligibilityGateway gateway,
) async {
  final bloc = await _startBusinessBloc(gateway);

  await pumpLocalized(
    tester,
    BusinessProfilePage(
      business: _businessSeed(),
      onNavChanged: (_) {},
      bloc: bloc,
    ),
  );

  await tester.tap(find.text('التقييمات'));
  await settleFrames(tester);
}

Future<void> _openProductReviews(
  WidgetTester tester,
  ReviewEligibilityGateway gateway,
) async {
  final bloc = await _startProductBloc(gateway);

  await pumpLocalized(
    tester,
    ProductDetailsPage(
      business: _businessSeed(),
      product: catalogProduct(),
      bloc: bloc,
    ),
  );

  await tester.tap(find.text('التقييمات'));
  await settleFrames(tester);
}

void _expectComposerClosed() {
  expect(find.text('نشر'), findsNothing);
  expect(find.byType(TextField), findsNothing);
}

void _expectComposerOpen() {
  expect(find.text('نشر'), findsOneWidget);
  expect(find.byType(TextField), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadAppTranslations);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('business review eligibility UI', () {
    testWidgets('guest sees sign-in guidance and no business review composer', (
      tester,
    ) async {
      final gateway = _FakeEligibilityGateway();

      await _openBusinessReviews(tester, gateway);

      expect(
        find.text('سجّل الدخول للتحقق من أهليتك لكتابة تقييم.'),
        findsOneWidget,
      );
      _expectComposerClosed();
      expect(gateway.businessCalls, 0);
    });

    testWidgets(
      'business account sees customer-only guidance and no composer',
      (tester) async {
        useAuthenticatedSession(business: true);

        final gateway = _FakeEligibilityGateway();

        await _openBusinessReviews(tester, gateway);

        expect(
          find.text('يمكن إرسال التقييمات من حساب عميل فقط.'),
          findsOneWidget,
        );
        _expectComposerClosed();
        expect(gateway.businessCalls, 0);
      },
    );

    testWidgets(
      'ineligible customer sees delivered-purchase guidance and no composer',
      (tester) async {
        useAuthenticatedSession();

        final gateway = _FakeEligibilityGateway(
          businessDecision: const ReviewEligibilityDecision(
            eligible: false,
            reason: ReviewEligibilityReason.deliveredPurchaseRequired,
          ),
        );

        await _openBusinessReviews(tester, gateway);

        expect(
          find.text('يمكنك تقييم هذا المتجر بعد استلام طلب مكتمل منه.'),
          findsOneWidget,
        );
        _expectComposerClosed();
        expect(gateway.businessCalls, 1);
      },
    );

    testWidgets('eligible customer sees the business review composer', (
      tester,
    ) async {
      useAuthenticatedSession();

      final gateway = _FakeEligibilityGateway();

      await _openBusinessReviews(tester, gateway);

      _expectComposerOpen();
      expect(gateway.businessCalls, 1);
    });
  });

  group('product review eligibility UI', () {
    testWidgets('guest sees sign-in guidance and no product review composer', (
      tester,
    ) async {
      final gateway = _FakeEligibilityGateway();

      await _openProductReviews(tester, gateway);

      expect(
        find.text('سجّل الدخول للتحقق من أهليتك لكتابة تقييم.'),
        findsOneWidget,
      );
      _expectComposerClosed();
      expect(gateway.productCalls, 0);
    });

    testWidgets(
      'business account sees customer-only guidance and no product composer',
      (tester) async {
        useAuthenticatedSession(business: true);

        final gateway = _FakeEligibilityGateway();

        await _openProductReviews(tester, gateway);

        expect(
          find.text('يمكن إرسال التقييمات من حساب عميل فقط.'),
          findsOneWidget,
        );
        _expectComposerClosed();
        expect(gateway.productCalls, 0);
      },
    );

    testWidgets(
      'ineligible customer sees exact-product purchase guidance and no composer',
      (tester) async {
        useAuthenticatedSession();

        final gateway = _FakeEligibilityGateway(
          productDecision: const ReviewEligibilityDecision(
            eligible: false,
            reason: ReviewEligibilityReason.deliveredPurchaseRequired,
          ),
        );

        await _openProductReviews(tester, gateway);

        expect(
          find.text('يمكنك تقييم هذا المنتج بعد استلام طلب مكتمل يحتوي عليه.'),
          findsOneWidget,
        );
        _expectComposerClosed();
        expect(gateway.productCalls, 1);
      },
    );

    testWidgets('eligible customer sees the product review composer', (
      tester,
    ) async {
      useAuthenticatedSession();

      final gateway = _FakeEligibilityGateway();

      await _openProductReviews(tester, gateway);

      _expectComposerOpen();
      expect(gateway.productCalls, 1);
    });
  });
}
