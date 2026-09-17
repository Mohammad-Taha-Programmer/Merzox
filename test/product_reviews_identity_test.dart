import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/widgets/remote_circle_avatar.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/home/presentation/bloc/home_state_.dart';
import 'package:merzox/features/product_details/bloc/product_details_bloc.dart';
import 'package:merzox/features/product_details/bloc/product_details_event.dart';
import 'package:merzox/features/product_details/bloc/product_details_state.dart';
import 'package:merzox/features/product_details/pages/product_details_page.dart';
import 'package:merzox/features/reviews/widgets/reviewer_badge.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/services/review_eligibility_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_test_fixtures.dart';
import 'localization_test_harness.dart';

/// Who wrote it, and who is about to.
///
/// The reviews tab drew a rating, a paragraph, and a blank blue disc that was
/// never filled in - so every reviewer looked like the same anonymous person,
/// and the reader had no way to tell one from the next. And nothing on the
/// page said which account was about to publish under the box.
const String _businessId = '64b000000000000000000001';

const String _reader = 'محمد أمين';

final List<BusinessReviewApiModel> _reviews = <BusinessReviewApiModel>[
  BusinessReviewApiModel(
    id: 'r1',
    userName: 'سلمى حدّاد',
    userAvatarUrl: 'https://example.invalid/salma.jpg',
    rating: 4,
    comment: 'وصل سريعاً والتغليف ممتاز.',
    createdAt: DateTime.utc(2026, 9, 1),
  ),
  BusinessReviewApiModel(
    id: 'r2',
    userName: 'رامي عبد الله',
    userAvatarUrl: '',
    rating: 3,
    // Nothing written: a rating on its own is a whole review.
    comment: '',
    createdAt: DateTime.utc(2026, 8, 20),
  ),
];

class _ProductApi extends ApiService {
  final BusinessProductApiModel product;

  _ProductApi(this.product);

  @override
  Future<BusinessProductApiModel> businessProduct({
    required String businessId,
    required String productId,
  }) async => product;

  @override
  Future<List<BusinessReviewApiModel>> productReviews({
    required String businessId,
    required String productId,
  }) async => _reviews;
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
    await loadAppTranslations();
  });

  void useSession({String name = _reader}) {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AuthBloc.sessionKey: true,
      AuthBloc.tokenKey: 'reviews-test-token',
      AuthBloc.userTypeKey: 'customer',
      if (name.isNotEmpty) AuthBloc.nameKey: name,
    });
  }

  setUp(useSession);

  /// Opens the product page on its reviews tab.
  Future<void> pumpReviews(WidgetTester tester) async {
    final BusinessProductApiModel product = catalogProduct(
      name: 'أساس فت مي',
      description: 'وصف قصير.',
    );
    final ProductDetailsBloc bloc = ProductDetailsBloc(
      apiService: _ProductApi(product),
      reviewEligibilityGateway: const _EligibleReviewer(),
    );
    // Not awaited: `close` does not complete once the page has been pumped,
    // and awaiting it in teardown hangs the whole file.
    addTearDown(() => unawaited(bloc.close()));

    final Future<ProductDetailsState> ready = bloc.stream.firstWhere(
      (ProductDetailsState state) =>
          state.detailsStatus == ProductDetailsSectionStatus.ready &&
          state.reviews.length == _reviews.length,
    );
    bloc.add(
      ProductDetailsStarted(businessId: _businessId, initialProduct: product),
    );
    await ready;

    bloc.add(const ProductDetailsTabChanged(1));
    await bloc.stream.firstWhere(
      (ProductDetailsState state) => state.selectedTabIndex == 1,
    );

    await pumpLocalized(
      tester,
      ProductDetailsPage(
        business: const HomeBusiness(
          id: _businessId,
          name: 'متجر الياسمين',
          category: 'مستحضرات تجميل',
          address: 'رام الله',
          products: <String>[],
          rating: 0,
          colorValue: 0xffdeeef8,
        ),
        product: product,
        bloc: bloc,
      ),
    );
  }

  group('the account about to write', () {
    testWidgets('its name and picture sit above the box', (
      WidgetTester tester,
    ) async {
      await pumpReviews(tester);

      final Finder name = find.byKey(
        const ValueKey<String>('productDetails.reviewerIdentity'),
      );
      expect(tester.widget<Text>(name).data, _reader);

      // Above the box it is about to be spent on, not below it.
      expect(
        tester.getBottomLeft(name).dy,
        lessThan(tester.getTopLeft(find.byType(TextField)).dy),
      );
    });

    testWidgets('a guest is named as nobody at all', (
      WidgetTester tester,
    ) async {
      // A figure beside the word for an unnamed account says less than
      // nothing: the row exists to answer "which account is this", and for a
      // guest there is no answer yet.
      useSession(name: '');
      await pumpReviews(tester);

      expect(
        find.byKey(const ValueKey<String>('productDetails.reviewerIdentity')),
        findsNothing,
      );
    });
  });

  group('the heading over the list', () {
    testWidgets('the words lead and the tally trails', (
      WidgetTester tester,
    ) async {
      await pumpReviews(tester);

      final double heading = tester
          .getCenter(
            find.byKey(const ValueKey<String>('productDetails.allReviews')),
          )
          .dx;
      final double tally = tester
          .getCenter(
            find.byKey(const ValueKey<String>('productDetails.reviewCount')),
          )
          .dx;

      // Arabic reads from the right, so the heading is the right-hand one.
      expect(heading, greaterThan(tally));
    });

    testWidgets('the tally counts the reviews', (WidgetTester tester) async {
      await pumpReviews(tester);

      expect(find.text('(${_reviews.length} تقييم)'), findsOneWidget);
    });
  });

  group('each review says who wrote it', () {
    testWidgets('by name and by picture', (WidgetTester tester) async {
      await pumpReviews(tester);

      for (final BusinessReviewApiModel review in _reviews) {
        final Finder name = find.byKey(
          ValueKey<String>('productDetails.reviewer.${review.id}'),
        );
        expect(tester.widget<Text>(name).data, review.userName);
      }

      // One for each review, and one more for the reader above them.
      expect(find.byType(ReviewerBadge), findsNWidgets(_reviews.length + 1));
      expect(
        tester
            .widgetList<RemoteCircleAvatar>(find.byType(RemoteCircleAvatar))
            .map((RemoteCircleAvatar avatar) => avatar.url),
        contains(_reviews.first.userAvatarUrl),
      );
    });

    testWidgets('with the rating at the other end of the line', (
      WidgetTester tester,
    ) async {
      await pumpReviews(tester);

      final Finder name = find.byKey(
        const ValueKey<String>('productDetails.reviewer.r1'),
      );
      // The figure that goes with the stars, which is on that end with them.
      final Finder rating = find.text('(4.0)');

      // The reviewer at the reading edge, the rating opposite them.
      expect(
        tester.getCenter(name).dx,
        greaterThan(tester.getCenter(rating).dx),
      );
    });

    testWidgets('and the picture leads the name', (WidgetTester tester) async {
      await pumpReviews(tester);

      final Finder name = find.byKey(
        const ValueKey<String>('productDetails.reviewer.r1'),
      );
      final Finder badge = find
          .ancestor(of: name, matching: find.byType(ReviewerBadge))
          .first;
      final Finder picture = find.descendant(
        of: badge,
        matching: find.byType(RemoteCircleAvatar),
      );

      expect(
        tester.getCenter(picture).dx,
        greaterThan(tester.getCenter(name).dx),
      );
    });

    testWidgets('and the words underneath both', (WidgetTester tester) async {
      await pumpReviews(tester);

      final Finder name = find.byKey(
        const ValueKey<String>('productDetails.reviewer.r1'),
      );
      final Finder comment = find.byKey(
        const ValueKey<String>('productDetails.reviewComment.r1'),
      );

      expect(tester.widget<Text>(comment).data, _reviews.first.comment);
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
        find.byKey(const ValueKey<String>('productDetails.reviewComment.r2')),
        findsNothing,
      );
      // But the review itself is still there.
      expect(
        find.byKey(const ValueKey<String>('productDetails.reviewer.r2')),
        findsOneWidget,
      );
    });
  });
}
