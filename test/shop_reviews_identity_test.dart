import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/widgets/remote_circle_avatar.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_bloc.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_event.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_state.dart';
import 'package:merzox/features/business_profile/business_profile_view_mode.dart';
import 'package:merzox/features/business_profile/pages/business_profile_page.dart';
import 'package:merzox/features/home/presentation/bloc/home_state_.dart';
import 'package:merzox/features/reviews/widgets/reviewer_badge.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/services/review_eligibility_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'golden/merzox_golden_harness.dart';

/// Who wrote it, and who is about to - on the shop's own reviews.
///
/// The product's reviews were given faces, a tally and a shape; the shop's
/// were left drawing a blank disc, a heading with no count beside it, and a
/// rating wedged into a column under the name.
const String _businessId = '64b000000000000000000001';

const String _reader = 'محمد أمين';

final List<Map<String, dynamic>> _reviews = <Map<String, dynamic>>[
  <String, dynamic>{
    'id': 'r1',
    'userName': 'سلمى حدّاد',
    'userAvatarUrl': 'https://example.invalid/salma.jpg',
    'rating': 4,
    'comment': 'خدمة ممتازة وأسعار منافسة.',
    'createdAt': '2026-09-01T00:00:00.000Z',
  },
  <String, dynamic>{
    'id': 'r2',
    'userName': 'رامي عبد الله',
    'userAvatarUrl': '',
    'rating': 3,
    // Nothing written: a rating on its own is a whole review.
    'comment': '',
    'createdAt': '2026-08-20T00:00:00.000Z',
  },
];

class _ShopApi extends ApiService {
  @override
  Future<BusinessDetailApiModel> business({required String businessId}) async {
    return BusinessDetailApiModel.fromJson(<String, dynamic>{
      'id': businessId,
      'publicId': '93872',
      'name': 'البتول كوزماتيكس',
      'category': 'مستحضرات تجميل',
      'address': 'سرطة سلفيت',
      'logoUrl': '',
      'products': <Map<String, dynamic>>[],
      'productCount': 0,
      'rating': 4,
      'ratingCount': _reviews.length,
      'colorValue': 0xffdeeef8,
    });
  }

  @override
  Future<List<BusinessProductApiModel>> businessProducts({
    required String businessId,
    required String classification,
  }) async => const <BusinessProductApiModel>[];

  @override
  Future<List<BusinessReviewApiModel>> businessReviews({
    required String businessId,
  }) async => _reviews.map(BusinessReviewApiModel.fromJson).toList();

  @override
  Future<FavoriteStatusApiResponse> favoriteStatus({
    required String token,
    required String businessId,
  }) async => FavoriteStatusApiResponse.fromJson(const <String, dynamic>{
    'businessFavorited': false,
    'productIds': <String>[],
  });
}

final class _EligibleReviewer implements ReviewEligibilityGateway {
  const _EligibleReviewer();

  @override
  Future<ReviewEligibilityDecision> businessEligibility({
    required String token,
    required String businessId,
  }) async => const ReviewEligibilityDecision(eligible: true, reason: null);

  @override
  Future<ReviewEligibilityDecision> productEligibility({
    required String token,
    required String businessId,
    required String productId,
  }) async => const ReviewEligibilityDecision(eligible: true, reason: null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
    await loadMerzoxGoldenDateSymbols();
    await loadMerzoxGoldenFonts();
  });

  void useSession({String name = _reader}) {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AuthBloc.sessionKey: true,
      AuthBloc.tokenKey: 'shop-reviews-token',
      AuthBloc.userTypeKey: 'customer',
      if (name.isNotEmpty) AuthBloc.nameKey: name,
    });
  }

  setUp(useSession);

  /// Opens the shop's page on its reviews tab.
  Future<void> pumpReviews(
    WidgetTester tester, {
    BusinessProfileViewMode viewMode = BusinessProfileViewMode.customer,
  }) async {
    final BusinessProfileBloc bloc = BusinessProfileBloc(
      apiService: _ShopApi(),
      reviewEligibilityGateway: const _EligibleReviewer(),
      viewMode: viewMode,
    );
    // Not awaited: `close` does not complete once the page has been pumped.
    addTearDown(() => unawaited(bloc.close()));

    final Future<BusinessProfileState> ready = bloc.stream.firstWhere(
      (BusinessProfileState state) =>
          state.status == BusinessProfileStatus.ready,
    );
    bloc.add(const BusinessProfileStarted(_businessId));
    await ready;

    bloc.add(const BusinessProfileMainTabChanged(2));
    await bloc.stream.firstWhere(
      (BusinessProfileState state) =>
          state.mainTabIndex == 2 && state.reviews.length == _reviews.length,
    );

    await pumpMerzoxGoldenPage(
      tester,
      withMerzoxGoldenDeviceInsets(
        BusinessProfilePage(
          business: const HomeBusiness(
            id: _businessId,
            name: 'البتول كوزماتيكس',
            category: 'مستحضرات تجميل',
            address: 'سرطة سلفيت',
            products: <String>[],
            rating: 4,
            colorValue: 0xffdeeef8,
          ),
          onNavChanged: (_) {},
          viewMode: viewMode,
          bloc: bloc,
        ),
      ),
    );
  }

  group('the account about to write', () {
    testWidgets('its name and picture sit above the stars', (
      WidgetTester tester,
    ) async {
      await pumpReviews(tester);

      final Finder name = find.byKey(
        const ValueKey<String>('storefront.reviewerIdentity'),
      );
      expect(tester.widget<Text>(name).data, _reader);

      expect(
        tester.getBottomLeft(name).dy,
        lessThan(tester.getTopLeft(find.byType(TextField)).dy),
      );
    });

    testWidgets('a guest is named as nobody at all', (
      WidgetTester tester,
    ) async {
      useSession(name: '');
      await pumpReviews(tester);

      expect(
        find.byKey(const ValueKey<String>('storefront.reviewerIdentity')),
        findsNothing,
      );
    });

    testWidgets('a merchant previewing their own shop is not named either', (
      WidgetTester tester,
    ) async {
      // There is no composer under it in preview, and naming the account
      // above a box that is not there would say nothing.
      await pumpReviews(
        tester,
        viewMode: BusinessProfileViewMode.merchantPreview,
      );

      expect(
        find.byKey(const ValueKey<String>('storefront.reviewerIdentity')),
        findsNothing,
      );
      // The published reviews are still shown, because that is what a
      // customer sees.
      expect(
        find.byKey(const ValueKey<String>('storefront.reviewer.r1')),
        findsOneWidget,
      );
    });
  });

  group('the heading over the list', () {
    testWidgets('carries a tally, at the other end of the line', (
      WidgetTester tester,
    ) async {
      await pumpReviews(tester);

      expect(find.text('(${_reviews.length} تقييم)'), findsOneWidget);

      final double heading = tester
          .getCenter(
            find.byKey(const ValueKey<String>('storefront.allReviews')),
          )
          .dx;
      final double tally = tester
          .getCenter(
            find.byKey(const ValueKey<String>('storefront.reviewCount')),
          )
          .dx;

      // Arabic reads from the right, so the heading is the right-hand one.
      expect(heading, greaterThan(tally));
    });
  });

  group('each review says who wrote it', () {
    testWidgets('by name and by picture', (WidgetTester tester) async {
      await pumpReviews(tester);

      for (final Map<String, dynamic> review in _reviews) {
        final Finder name = find.byKey(
          ValueKey<String>('storefront.reviewer.${review['id']}'),
        );
        expect(tester.widget<Text>(name).data, review['userName']);
      }

      // One for each review, and one more for the reader above them.
      expect(find.byType(ReviewerBadge), findsNWidgets(_reviews.length + 1));
      expect(
        tester
            .widgetList<RemoteCircleAvatar>(find.byType(RemoteCircleAvatar))
            .map((RemoteCircleAvatar avatar) => avatar.url),
        contains(_reviews.first['userAvatarUrl']),
      );
    });

    testWidgets('with the rating at the other end of the line', (
      WidgetTester tester,
    ) async {
      await pumpReviews(tester);

      final Finder name = find.byKey(
        const ValueKey<String>('storefront.reviewer.r1'),
      );
      final Finder rating = find.text('(4.0)');

      expect(
        tester.getCenter(name).dx,
        greaterThan(tester.getCenter(rating).dx),
      );
    });

    testWidgets('and the words underneath both', (WidgetTester tester) async {
      await pumpReviews(tester);

      final Finder name = find.byKey(
        const ValueKey<String>('storefront.reviewer.r1'),
      );
      final Finder comment = find.byKey(
        const ValueKey<String>('storefront.reviewComment.r1'),
      );

      expect(tester.widget<Text>(comment).data, _reviews.first['comment']);
      expect(
        tester.getTopLeft(comment).dy,
        greaterThan(tester.getBottomLeft(name).dy),
      );
      // The whole width of the entry, not the sliver left beside the picture.
      expect(
        tester.getSize(comment).width,
        greaterThan(tester.getSize(name).width),
      );
    });

    testWidgets('a rating with nothing written draws no empty paragraph', (
      WidgetTester tester,
    ) async {
      await pumpReviews(tester);

      expect(
        find.byKey(const ValueKey<String>('storefront.reviewComment.r2')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('storefront.reviewer.r2')),
        findsOneWidget,
      );
    });
  });
}
