import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_bloc.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_event.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_state.dart';
import 'package:merzox/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_test_fixtures.dart';

class _FakeBusinessProfileApi extends ApiService {
  final bool failDetails;
  final bool failProducts;
  final bool failReviews;

  _FakeBusinessProfileApi({
    this.failDetails = false,
    this.failProducts = false,
    this.failReviews = false,
  });

  @override
  Future<BusinessDetailApiModel> business({required String businessId}) async {
    if (failDetails) throw StateError('details offline');
    return catalogBusinessDetail(id: businessId);
  }

  @override
  Future<List<BusinessProductApiModel>> businessProducts({
    required String businessId,
    required String classification,
  }) async {
    if (failProducts) throw StateError('products offline');
    return const [];
  }

  @override
  Future<List<BusinessReviewApiModel>> businessReviews({
    required String businessId,
  }) async {
    if (failReviews) throw StateError('reviews offline');
    return const [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'zero business products and reviews remain empty without fallbacks',
    () async {
      final bloc = BusinessProfileBloc(apiService: _FakeBusinessProfileApi());
      addTearDown(bloc.close);

      final startedFuture = bloc.stream.firstWhere(
        (state) =>
            state.detailsStatus == BusinessProfileSectionStatus.ready &&
            state.productsStatus == BusinessProfileSectionStatus.ready,
      );
      bloc.add(const BusinessProfileStarted('64b000000000000000000001'));
      final started = await startedFuture;

      expect(started.business?.name, 'Test business');
      expect(started.products, isEmpty);

      final reviewsFuture = bloc.stream.firstWhere(
        (state) => state.reviewsStatus == BusinessProfileSectionStatus.ready,
      );
      bloc.add(const BusinessProfileMainTabChanged(2));
      final reviewsState = await reviewsFuture;

      expect(reviewsState.reviews, isEmpty);
    },
  );

  test(
    'business profile exposes section failures without fallback data',
    () async {
      final bloc = BusinessProfileBloc(
        apiService: _FakeBusinessProfileApi(
          failDetails: true,
          failProducts: true,
          failReviews: true,
        ),
      );
      addTearDown(bloc.close);

      final startedFuture = bloc.stream.firstWhere(
        (state) =>
            state.detailsStatus == BusinessProfileSectionStatus.failure &&
            state.productsStatus == BusinessProfileSectionStatus.failure,
      );
      bloc.add(const BusinessProfileStarted('64b000000000000000000001'));
      final started = await startedFuture;

      expect(started.business, isNull);
      expect(started.products, isEmpty);

      final reviewsFuture = bloc.stream.firstWhere(
        (state) => state.reviewsStatus == BusinessProfileSectionStatus.failure,
      );
      bloc.add(const BusinessProfileMainTabChanged(2));
      final reviewsState = await reviewsFuture;

      expect(reviewsState.reviews, isEmpty);
      expect(reviewsState.reviewsError, isNotEmpty);
    },
  );
}
