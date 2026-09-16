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

import 'catalog_test_fixtures.dart';
import 'golden/merzox_golden_harness.dart';

/// Pull the shop's page down, and get the shop again.
///
/// Three tabs, three requests, and a reader who pulls has no way to say which
/// one they meant - so the pull means all of them. What it must not do is
/// empty the page it is refreshing: a storefront blanked under the indicator
/// would be a worse answer than the one that is a minute old.
const String _businessId = '64b000000000000000000001';

class _CountingApi extends ApiService {
  int detailCalls = 0;
  int productCalls = 0;
  int reviewCalls = 0;

  /// The classification each products request asked for, in order.
  final List<String> classifications = <String>[];

  /// Set to make the next detail request fail.
  bool detailsFail = false;

  /// Held open to keep a refresh in flight.
  Completer<void>? gate;

  String shopName = 'متجر الياسمين';
  List<Map<String, dynamic>> products = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> reviews = <Map<String, dynamic>>[];

  @override
  Future<BusinessDetailApiModel> business({required String businessId}) async {
    detailCalls += 1;
    await gate?.future;

    if (detailsFail) throw StateError('the shop is offline');

    return BusinessDetailApiModel.fromJson(<String, dynamic>{
      'id': businessId,
      'publicId': '0020101',
      'name': shopName,
      'category': 'مستحضرات تجميل',
      'address': 'رام الله',
      'logoUrl': '',
      'products': products,
      'productCount': products.length,
      'rating': 4.6,
      'ratingCount': 12,
      'colorValue': 0xffdeeef8,
    });
  }

  @override
  Future<List<BusinessProductApiModel>> businessProducts({
    required String businessId,
    required String classification,
  }) async {
    productCalls += 1;
    classifications.add(classification);
    await gate?.future;

    return products
        .map(BusinessProductApiModel.fromJson)
        .toList(growable: false);
  }

  @override
  Future<List<BusinessReviewApiModel>> businessReviews({
    required String businessId,
  }) async {
    reviewCalls += 1;
    await gate?.future;

    return reviews.map(BusinessReviewApiModel.fromJson).toList(growable: false);
  }

  @override
  Future<FavoriteStatusApiResponse> favoriteStatus({
    required String token,
    required String businessId,
  }) async => FavoriteStatusApiResponse.fromJson(const <String, dynamic>{
    'businessFavorited': false,
    'productIds': <String>[],
  });
}

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

  Future<BusinessProfileBloc> openShop(_CountingApi api) async {
    final BusinessProfileBloc bloc = BusinessProfileBloc(
      apiService: api,
      reviewEligibilityGateway: _NoReviewEligibility(),
    );
    addTearDown(() => unawaited(bloc.close()));

    final Future<BusinessProfileState> ready = bloc.stream.firstWhere(
      (BusinessProfileState state) =>
          state.status == BusinessProfileStatus.ready,
    );
    bloc.add(const BusinessProfileStarted(_businessId));
    await ready;

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

  test('one pull fetches all three tabs', () async {
    final _CountingApi api = _CountingApi();
    final BusinessProfileBloc bloc = await openShop(api);

    // Opening the page fetches the shop and the shelf, and leaves the reviews
    // until somebody asks for them.
    expect(api.detailCalls, 1);
    expect(api.productCalls, 1);
    expect(api.reviewCalls, 0);

    await refreshStorefront(bloc);

    expect(api.detailCalls, 2);
    expect(api.productCalls, 2);
    expect(api.reviewCalls, 1, reason: 'the reviews tab was not refreshed');
    expect(bloc.state.isRefreshing, isFalse);
  });

  test('it asks for the shelf the reader is looking at', () async {
    final _CountingApi api = _CountingApi();
    final BusinessProfileBloc bloc = await openShop(api);

    final Future<BusinessProfileState> filtered = bloc.stream.firstWhere(
      (BusinessProfileState state) =>
          state.productClassification == 'bestSelling' &&
          state.productsStatus == BusinessProfileSectionStatus.ready,
    );
    bloc.add(const BusinessProfileProductFilterChanged('bestSelling'));
    await filtered;

    await refreshStorefront(bloc);

    expect(api.classifications.last, 'bestSelling');
  });

  test('the page it is refreshing is not emptied first', () async {
    // The indicator at the top is the progress. Three tabs blanked underneath
    // it would replace a page a minute old with nothing at all.
    final _CountingApi api = _CountingApi()
      ..products = <Map<String, dynamic>>[
        catalogProductJson(name: 'أحمر شفاه'),
      ];
    final BusinessProfileBloc bloc = await openShop(api);

    expect(bloc.state.products, hasLength(1));

    api.gate = Completer<void>();
    final Future<void> refresh = refreshStorefront(bloc);
    await Future<void>.delayed(Duration.zero);

    expect(bloc.state.isRefreshing, isTrue);
    expect(bloc.state.business?.name, 'متجر الياسمين');
    expect(bloc.state.products, hasLength(1));
    expect(bloc.state.productsStatus, BusinessProfileSectionStatus.ready);

    api.gate!.complete();
    await refresh;
  });

  test('a section that fails keeps what it had, and says it failed', () async {
    final _CountingApi api = _CountingApi()
      ..products = <Map<String, dynamic>>[
        catalogProductJson(name: 'أحمر شفاه'),
      ];
    final BusinessProfileBloc bloc = await openShop(api);

    api.detailsFail = true;
    await refreshStorefront(bloc);

    expect(bloc.state.business?.name, 'متجر الياسمين');
    expect(bloc.state.detailsStatus, BusinessProfileSectionStatus.failure);
    expect(bloc.state.detailsError, isNotEmpty);
    // And the sections that answered are the ones that answered.
    expect(bloc.state.productsStatus, BusinessProfileSectionStatus.ready);
  });

  test('it brings back what changed', () async {
    final _CountingApi api = _CountingApi();
    final BusinessProfileBloc bloc = await openShop(api);

    api.shopName = 'متجر الياسمين للتجميل';
    api.products = <Map<String, dynamic>>[catalogProductJson(name: 'مسكارا')];
    await refreshStorefront(bloc);

    expect(bloc.state.business?.name, 'متجر الياسمين للتجميل');
    expect(bloc.state.products.single.name, 'مسكارا');
  });

  test('a second pull joins the one already running', () async {
    final _CountingApi api = _CountingApi();
    final BusinessProfileBloc bloc = await openShop(api);

    api.gate = Completer<void>();
    final Future<void> first = refreshStorefront(bloc);
    await Future<void>.delayed(Duration.zero);
    final Future<void> second = refreshStorefront(bloc);

    api.gate!.complete();
    await Future.wait(<Future<void>>[first, second]);

    // One set of requests, not two.
    expect(api.detailCalls, 2);
    expect(api.reviewCalls, 1);
  });

  testWidgets('and the gesture is wired to it', (WidgetTester tester) async {
    final _CountingApi api = _CountingApi();
    final BusinessProfileBloc bloc = await openShop(api);

    await pumpMerzoxGoldenPage(tester, page(bloc));

    expect(api.detailCalls, 1);

    await tester.fling(find.byType(ListView), const Offset(0, 400), 1200);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(api.detailCalls, 2);
    expect(api.reviewCalls, 1);
  });
}
