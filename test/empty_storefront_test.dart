import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_bloc.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_event.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_state.dart';
import 'package:merzox/features/business_profile/pages/business_profile_page.dart';
import 'package:merzox/features/home/presentation/bloc/home_state_.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/services/review_eligibility_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'golden/merzox_golden_harness.dart';

/// A shop that has registered and sells nothing yet.
///
/// The likeliest state on a new deployment, and the one the customer reaches
/// first: a merchant signs up before adding a product. The storefront has to
/// say the shelf is empty rather than draw a blank tab.
///
/// This lives apart from `empty_database_test.dart` because it needs the
/// golden harness and nothing else. The storefront lays its filter row out at
/// 375 only in the app's own font, and two localization initialisations in one
/// file do not settle - the page then never completes a frame, which is what
/// made this surface look unverifiable.
const String _businessId = '64b000000000000000000001';

class _EmptyStorefrontApi extends ApiService {
  @override
  Future<BusinessDetailApiModel> business({required String businessId}) async =>
      BusinessDetailApiModel.fromJson(<String, dynamic>{
        'id': businessId,
        'publicId': '0020101',
        'name': 'متجر الياسمين',
        'category': 'مستحضرات تجميل',
        'address': 'رام الله',
        'products': <Map<String, dynamic>>[],
        'productCount': 0,
        'rating': 0,
        'ratingCount': 0,
        'colorValue': 0xffdeeef8,
      });

  @override
  Future<List<BusinessProductApiModel>> businessProducts({
    required String businessId,
    required String classification,
  }) async => const <BusinessProductApiModel>[];

  @override
  Future<List<BusinessReviewApiModel>> businessReviews({
    required String businessId,
  }) async => const <BusinessReviewApiModel>[];

  @override
  Future<FavoriteStatusApiResponse> favoriteStatus({
    required String token,
    required String businessId,
  }) async => FavoriteStatusApiResponse.fromJson(const <String, dynamic>{
    'businessFavorited': false,
    'productIds': <String>[],
  });
}

/// Nobody has bought anything, so nobody may review anything. The real gateway
/// would reach the network to find that out.
final class _NoReviewEligibility implements ReviewEligibilityGateway {
  @override
  Future<ReviewEligibilityDecision> businessEligibility({
    required String token,
    required String businessId,
  }) async => const ReviewEligibilityDecision(eligible: false, reason: null);

  @override
  Future<ReviewEligibilityDecision> productEligibility({
    required String token,
    required String businessId,
    required String productId,
  }) async => const ReviewEligibilityDecision(eligible: false, reason: null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
    await loadMerzoxGoldenDateSymbols();
    await loadMerzoxGoldenFonts();
  });

  Future<BusinessProfileBloc> openTab(int index) async {
    final BusinessProfileBloc bloc = BusinessProfileBloc(
      apiService: _EmptyStorefrontApi(),
      reviewEligibilityGateway: _NoReviewEligibility(),
    );
    // Not awaited on purpose. `BusinessProfileBloc.close` does not complete
    // after a page has been pumped inside `runAsync`, and awaiting it hangs
    // the whole file in teardown - the same reason the golden seeds close
    // their blocs this way.
    addTearDown(() => unawaited(bloc.close()));

    final Future<BusinessProfileState> ready = bloc.stream.firstWhere(
      (BusinessProfileState state) =>
          state.status == BusinessProfileStatus.ready,
    );
    bloc.add(const BusinessProfileStarted(_businessId));
    await ready;

    final Future<BusinessProfileState> section = bloc.stream.firstWhere(
      (BusinessProfileState state) =>
          state.mainTabIndex == index &&
          (index == 1 ? state.productsStatus : state.reviewsStatus) ==
              BusinessProfileSectionStatus.ready,
    );
    bloc.add(BusinessProfileMainTabChanged(index));
    await section;

    return bloc;
  }

  Widget page(BusinessProfileBloc bloc) => withMerzoxGoldenDeviceInsets(
    BusinessProfilePage(
      business: const HomeBusiness(
        id: _businessId,
        name: 'متجر الياسمين',
        category: 'مستحضرات تجميل',
        address: 'رام الله',
        products: <String>[],
        rating: 0,
        colorValue: 0xffdeeef8,
      ),
      onNavChanged: (_) {},
      bloc: bloc,
    ),
  );

  testWidgets('a shop with no products says the shelf is empty', (
    WidgetTester tester,
  ) async {
    final BusinessProfileBloc bloc = await openTab(1);
    expect(bloc.state.products, isEmpty);

    await pumpMerzoxGoldenPage(tester, page(bloc));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('لا توجد منتجات متاحة ضمن هذا التصنيف.'), findsOneWidget);
    // The shop itself is still drawn around the empty shelf.
    expect(find.text('متجر الياسمين'), findsWidgets);
    expect(find.text('0 منتج'), findsOneWidget);
  });

  testWidgets('a shop nobody has reviewed says so', (
    WidgetTester tester,
  ) async {
    final BusinessProfileBloc bloc = await openTab(2);
    expect(bloc.state.reviews, isEmpty);

    await pumpMerzoxGoldenPage(tester, page(bloc));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('لا توجد تقييمات حتى الآن.'), findsOneWidget);
  });
}
