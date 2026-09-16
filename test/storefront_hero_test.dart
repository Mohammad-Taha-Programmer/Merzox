import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/core/widgets/merzox_icons.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_bloc.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_event.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_state.dart';
import 'package:merzox/features/business_profile/pages/business_profile_page.dart';
import 'package:merzox/features/home/presentation/bloc/home_state_.dart';
import 'package:merzox/features/product_details/pages/product_details_page.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/services/review_eligibility_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_test_fixtures.dart';
import 'golden/merzox_golden_harness.dart';

/// The head of a shop's own page: the badge, the face, and the picture.
///
/// Three facts are drawn up there and two of them were not facts about the
/// shop at all. The badge carried the shop's category, which every shop has,
/// so it distinguished none of them. The face was a literal `🙂` in the
/// source - the same face over every shop in the app, and drawn by whatever
/// emoji font the phone happened to carry. And the picture was never read: a
/// merchant who set a logo saw it on their settings screen, in the home list
/// and on a product page, and saw a letter on their own storefront.
const String _businessId = '64b000000000000000000001';

class _ShopApi extends ApiService {
  final double rating;
  final String logoUrl;
  final List<Map<String, dynamic>> products;

  _ShopApi({
    required this.rating,
    this.logoUrl = '',
    this.products = const <Map<String, dynamic>>[],
  });

  @override
  Future<BusinessDetailApiModel> business({required String businessId}) async =>
      BusinessDetailApiModel.fromJson(<String, dynamic>{
        'id': businessId,
        'publicId': '0020101',
        'name': 'متجر الياسمين',
        'category': 'مستحضرات تجميل',
        'address': 'رام الله',
        'logoUrl': logoUrl,
        // So the third circle - the one that reaches the shop - is drawn at
        // all: it appears only for a shop that published a way to be reached.
        'socialLinks': <String, dynamic>{'instagram': 'yasmin.store'},
        'products': products,
        'productCount': products.length,
        'rating': rating,
        'ratingCount': 12,
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

  Future<BusinessProfileBloc> openShop({
    required double rating,
    String logoUrl = '',
    List<Map<String, dynamic>> products = const <Map<String, dynamic>>[],
  }) async {
    final BusinessProfileBloc bloc = BusinessProfileBloc(
      apiService: _ShopApi(
        rating: rating,
        logoUrl: logoUrl,
        products: products,
      ),
      reviewEligibilityGateway: _NoReviewEligibility(),
    );
    // Not awaited: `close` does not complete after a page has been pumped
    // inside `runAsync`, and awaiting it hangs the file in teardown.
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

  testWidgets('a shop at four stars is called one of the best, and smiles', (
    WidgetTester tester,
  ) async {
    await pumpMerzoxGoldenPage(tester, page(await openShop(rating: 4.6)));

    expect(find.text('أفضل المتاجر'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('storefront.mood.happy')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('storefront.mood.sad')),
      findsNothing,
    );
  });

  testWidgets('a shop below four stars says nothing, and does not smile', (
    WidgetTester tester,
  ) async {
    await pumpMerzoxGoldenPage(tester, page(await openShop(rating: 3.9)));

    expect(find.text('أفضل المتاجر'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('storefront.mood.sad')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('storefront.mood.happy')),
      findsNothing,
    );
  });

  testWidgets('exactly four stars is already the mark', (
    WidgetTester tester,
  ) async {
    // The boundary, stated once so "four stars and above" cannot quietly
    // become "above four stars".
    expect(isTopRatedShop(kTopShopRating), isTrue);
    expect(isTopRatedShop(kTopShopRating - 0.01), isFalse);

    await pumpMerzoxGoldenPage(tester, page(await openShop(rating: 4)));

    expect(find.text('أفضل المتاجر'), findsOneWidget);
  });

  testWidgets('the shop draws its own picture when it has one', (
    WidgetTester tester,
  ) async {
    await pumpMerzoxGoldenPage(
      tester,
      page(
        await openShop(
          rating: 4.6,
          logoUrl: 'https://example.test/yasmin-logo.png',
        ),
      ),
    );

    // The request is what is checked, not the pixels: a test cannot reach the
    // network, and what was wrong here was that nothing ever asked.
    final Finder logo = find.byKey(
      const ValueKey<String>('storefront.logo.$_businessId'),
    );
    expect(logo, findsOneWidget);
    expect(
      (tester.widget<Image>(logo).image as NetworkImage).url,
      'https://example.test/yasmin-logo.png',
    );
  });

  testWidgets('a shop with no picture keeps the letter it always drew', (
    WidgetTester tester,
  ) async {
    await pumpMerzoxGoldenPage(tester, page(await openShop(rating: 4.6)));

    expect(
      find.byKey(const ValueKey<String>('storefront.logo.$_businessId')),
      findsNothing,
    );
    expect(find.text('م'), findsOneWidget);
  });

  testWidgets('the storefront draws no bell of its own', (
    WidgetTester tester,
  ) async {
    // The app has one bell, floating above every screen from the router. The
    // storefront drew a second one underneath it: an icon with a hard-coded
    // unread dot, no tap, and nothing behind the dot.
    await pumpMerzoxGoldenPage(tester, page(await openShop(rating: 4.6)));

    expect(find.byIcon(MerzoxIcons.businessProfileNotifications), findsNothing);
  });

  testWidgets('the three circles are drawn in one colour', (
    WidgetTester tester,
  ) async {
    // And which colour: the deep blue the middle circle already wore. Naming
    // the constant makes the three agree with each other; this makes them
    // agree with the one that was right.
    expect(kStoreActionColour, MerzoxColors.kColor3D5A80);

    await pumpMerzoxGoldenPage(tester, page(await openShop(rating: 4.6)));

    for (final String name in <String>['share', 'chat', 'contact']) {
      final IconButton circle = tester.widget<IconButton>(
        find.byKey(ValueKey<String>('storefront.$name')),
      );
      expect(
        circle.style?.backgroundColor?.resolve(const <WidgetState>{}),
        kStoreActionColour,
        reason: 'the $name circle drew its own colour',
      );
    }
  });

  testWidgets('the services heading sits outside the services it heads', (
    WidgetTester tester,
  ) async {
    // Arabic reads right to left, so the heading takes the outer right edge
    // and the list runs leftwards from it. They used to be a heading above a
    // list that chose the opposite edge - `centerEnd`, which in Arabic is the
    // LEFT - so the two sat at opposite ends of the same section.
    await pumpMerzoxGoldenPage(tester, page(await openShop(rating: 4.6)));

    final Rect heading = tester.getRect(find.text('خدماتنا'));
    final Rect listed = tester.getRect(
      find.text('لا توجد خدمات متاحة حتى الآن.'),
    );

    expect(heading.right, greaterThan(listed.right));
  });

  group('a service', () {
    const String serviceId = '64c000000000000000000009';

    Map<String, dynamic> service({List<String> imageUrls = const <String>[]}) =>
        catalogProductJson(
          id: serviceId,
          name: 'قص شعر',
          imageUrls: imageUrls,
          isService: true,
        );

    testWidgets('shows the picture the merchant attached to it', (
      WidgetTester tester,
    ) async {
      // It is the same record as a product and carries the same picture
      // fields. The tile drew the same pair of cogs over every service in the
      // app instead.
      await pumpMerzoxGoldenPage(
        tester,
        page(
          await openShop(
            rating: 4.6,
            products: <Map<String, dynamic>>[
              service(imageUrls: <String>['https://example.test/haircut.png']),
            ],
          ),
        ),
      );

      final Finder picture = find.byKey(
        const ValueKey<String>('storefront.service.picture.$serviceId'),
      );
      expect(picture, findsOneWidget);
      expect(
        (tester.widget<Image>(picture).image as NetworkImage).url,
        'https://example.test/haircut.png',
      );
    });

    testWidgets('with no picture keeps the mark that stands in', (
      WidgetTester tester,
    ) async {
      await pumpMerzoxGoldenPage(
        tester,
        page(
          await openShop(
            rating: 4.6,
            products: <Map<String, dynamic>>[service()],
          ),
        ),
      );

      expect(
        find.byKey(
          const ValueKey<String>('storefront.service.picture.$serviceId'),
        ),
        findsNothing,
      );
      expect(
        find.byIcon(Icons.miscellaneous_services_outlined),
        findsOneWidget,
      );
    });

    testWidgets('opens when it is tapped', (WidgetTester tester) async {
      // A shop could describe what it does and a customer had no way to ask
      // for it: the tile was not tappable at all.
      await pumpMerzoxGoldenPage(
        tester,
        page(
          await openShop(
            rating: 4.6,
            products: <Map<String, dynamic>>[service()],
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('storefront.service.$serviceId')),
      );
      // Not `pumpAndSettle`: the page it opens starts a request that never
      // completes under test.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(ProductDetailsPage), findsOneWidget);
    });
  });
}
