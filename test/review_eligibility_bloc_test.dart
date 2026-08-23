import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_bloc.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_event.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_state.dart';
import 'package:merzox/features/product_details/bloc/product_details_bloc.dart';
import 'package:merzox/features/product_details/bloc/product_details_event.dart';
import 'package:merzox/features/product_details/bloc/product_details_state.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/services/review_eligibility_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_session_fixtures.dart';
import 'catalog_test_fixtures.dart';

class _FakeEligibilityGateway implements ReviewEligibilityGateway {
  ReviewEligibilityDecision businessDecision = const ReviewEligibilityDecision(
    eligible: true,
    reason: null,
  );

  ReviewEligibilityDecision productDecision = const ReviewEligibilityDecision(
    eligible: true,
    reason: null,
  );

  Object? businessError;
  Object? productError;

  int businessCalls = 0;
  int productCalls = 0;

  String? businessId;
  String? productBusinessId;
  String? productId;

  @override
  Future<ReviewEligibilityDecision> businessEligibility({
    required String token,
    required String businessId,
  }) async {
    businessCalls += 1;
    this.businessId = businessId;

    if (businessError != null) throw businessError!;

    return businessDecision;
  }

  @override
  Future<ReviewEligibilityDecision> productEligibility({
    required String token,
    required String businessId,
    required String productId,
  }) async {
    productCalls += 1;
    productBusinessId = businessId;
    this.productId = productId;

    if (productError != null) throw productError!;

    return productDecision;
  }
}

class _FakeBusinessApi extends ApiService {
  int reviewSubmits = 0;

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

  @override
  Future<BusinessReviewApiModel> submitBusinessReview({
    required String token,
    required String businessId,
    required int rating,
    required String comment,
  }) async {
    reviewSubmits += 1;
    return BusinessReviewApiModel.fromJson(const {
      'id': '64d000000000000000000001',
      'userName': 'Customer',
      'rating': 5,
      'comment': 'Good',
    });
  }
}

class _FakeProductApi extends ApiService {
  int reviewSubmits = 0;

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

  @override
  Future<ProductReviewSubmitResponse> submitProductReview({
    required String token,
    required String businessId,
    required String productId,
    required int rating,
    required String comment,
  }) async {
    reviewSubmits += 1;

    return ProductReviewSubmitResponse(
      review: BusinessReviewApiModel.fromJson(const {
        'id': '64d000000000000000000001',
        'userName': 'Customer',
        'rating': 5,
        'comment': 'Good',
      }),
      product: catalogProduct(id: productId),
    );
  }
}

Future<void> _startBusiness(BusinessProfileBloc bloc) async {
  final ready = bloc.stream.firstWhere(
    (state) => state.status == BusinessProfileStatus.ready,
  );

  bloc.add(const BusinessProfileStarted('64b000000000000000000001'));

  await ready;
}

Future<void> _startProduct(ProductDetailsBloc bloc) async {
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

Future<void> _drain() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.value();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'guest opens business reviews without an eligibility network call',
    () async {
      final gateway = _FakeEligibilityGateway();
      final bloc = BusinessProfileBloc(
        apiService: _FakeBusinessApi(),
        reviewEligibilityGateway: gateway,
      );
      addTearDown(bloc.close);

      await _startBusiness(bloc);

      final result = bloc.stream.firstWhere(
        (state) =>
            state.reviewEligibilityStatus ==
            ReviewEligibilityStatus.loginRequired,
      );

      bloc.add(const BusinessProfileMainTabChanged(2));

      await result;

      expect(gateway.businessCalls, 0);
    },
  );

  test(
    'business session is refused locally without an eligibility GET',
    () async {
      useAuthenticatedSession(business: true);

      final gateway = _FakeEligibilityGateway();
      final bloc = BusinessProfileBloc(
        apiService: _FakeBusinessApi(),
        reviewEligibilityGateway: gateway,
      );
      addTearDown(bloc.close);

      await _startBusiness(bloc);

      final result = bloc.stream.firstWhere(
        (state) =>
            state.reviewEligibilityStatus ==
            ReviewEligibilityStatus.customerAccountRequired,
      );

      bloc.add(const BusinessProfileMainTabChanged(2));

      await result;

      expect(gateway.businessCalls, 0);
    },
  );

  test(
    'customer business eligibility comes only from the server decision',
    () async {
      useAuthenticatedSession();

      final gateway = _FakeEligibilityGateway();
      final bloc = BusinessProfileBloc(
        apiService: _FakeBusinessApi(),
        reviewEligibilityGateway: gateway,
      );
      addTearDown(bloc.close);

      await _startBusiness(bloc);

      final result = bloc.stream.firstWhere(
        (state) =>
            state.reviewEligibilityStatus == ReviewEligibilityStatus.eligible,
      );

      bloc.add(const BusinessProfileMainTabChanged(2));

      await result;

      expect(gateway.businessCalls, 1);
      expect(gateway.businessId, '64b000000000000000000001');
    },
  );

  test(
    'delivered-purchase denial keeps the business composer closed',
    () async {
      useAuthenticatedSession();

      final gateway = _FakeEligibilityGateway()
        ..businessDecision = const ReviewEligibilityDecision(
          eligible: false,
          reason: ReviewEligibilityReason.deliveredPurchaseRequired,
        );

      final bloc = BusinessProfileBloc(
        apiService: _FakeBusinessApi(),
        reviewEligibilityGateway: gateway,
      );
      addTearDown(bloc.close);

      await _startBusiness(bloc);

      final result = bloc.stream.firstWhere(
        (state) =>
            state.reviewEligibilityStatus ==
            ReviewEligibilityStatus.deliveredPurchaseRequired,
      );

      bloc.add(const BusinessProfileMainTabChanged(2));

      await result;
    },
  );

  test('eligibility lookup failure fails closed', () async {
    useAuthenticatedSession();

    final gateway = _FakeEligibilityGateway()
      ..businessError = StateError('offline');

    final bloc = BusinessProfileBloc(
      apiService: _FakeBusinessApi(),
      reviewEligibilityGateway: gateway,
    );
    addTearDown(bloc.close);

    await _startBusiness(bloc);

    final result = bloc.stream.firstWhere(
      (state) =>
          state.reviewEligibilityStatus == ReviewEligibilityStatus.failure,
    );

    bloc.add(const BusinessProfileMainTabChanged(2));

    await result;
  });

  test(
    'product eligibility query carries the exact visible product id',
    () async {
      useAuthenticatedSession();

      final gateway = _FakeEligibilityGateway();
      final bloc = ProductDetailsBloc(
        apiService: _FakeProductApi(),
        reviewEligibilityGateway: gateway,
      );
      addTearDown(bloc.close);

      await _startProduct(bloc);

      final result = bloc.stream.firstWhere(
        (state) =>
            state.reviewEligibilityStatus == ReviewEligibilityStatus.eligible,
      );

      bloc.add(const ProductDetailsTabChanged(1));

      await result;

      expect(gateway.productCalls, 1);
      expect(gateway.productBusinessId, '64b000000000000000000001');
      expect(gateway.productId, '64c000000000000000000001');
    },
  );

  test(
    'review submission event cannot bypass an unchecked eligibility state',
    () async {
      useAuthenticatedSession();

      final api = _FakeBusinessApi();
      final bloc = BusinessProfileBloc(
        apiService: api,
        reviewEligibilityGateway: _FakeEligibilityGateway(),
      );
      addTearDown(bloc.close);

      await _startBusiness(bloc);

      bloc.add(
        const BusinessProfileReviewSubmitted(rating: 5, comment: 'Good'),
      );

      await _drain();

      expect(api.reviewSubmits, 0);
    },
  );

  test('eligible customer can submit after the server decision', () async {
    useAuthenticatedSession();

    final api = _FakeBusinessApi();
    final bloc = BusinessProfileBloc(
      apiService: api,
      reviewEligibilityGateway: _FakeEligibilityGateway(),
    );
    addTearDown(bloc.close);

    await _startBusiness(bloc);

    final eligible = bloc.stream.firstWhere(
      (state) =>
          state.reviewEligibilityStatus == ReviewEligibilityStatus.eligible,
    );

    bloc.add(const BusinessProfileMainTabChanged(2));
    await eligible;

    bloc.add(const BusinessProfileReviewSubmitted(rating: 5, comment: 'Good'));

    await _drain();

    expect(api.reviewSubmits, 1);
  });
}
