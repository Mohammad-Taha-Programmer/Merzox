import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_route_guard.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/features/business/preview/store_preview_page.dart';
import 'package:merzox/features/business/shell/business_bloc.dart';
import 'package:merzox/features/business/shell/business_shell_page.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_bloc.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_event.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_state.dart';
import 'package:merzox/features/business_profile/business_profile_view_mode.dart';
import 'package:merzox/features/business_profile/pages/business_profile_page.dart';
import 'package:merzox/features/home/presentation/bloc/home_state_.dart';
import 'package:merzox/features/product_details/pages/product_details_page.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/services/review_eligibility_service.dart';

import 'auth_session_fixtures.dart';
import 'catalog_test_fixtures.dart';
import 'localization_test_harness.dart';

/// MERZOX-GAP-001 - merchant store preview.
///
/// The invariant under test is "merchant preview = customer-visible truth, read
/// only". That splits into three provable claims, and every test below belongs
/// to exactly one of them:
///
///   1. the preview reads the same PUBLIC contracts a customer reads,
///   2. no owner-private value can travel into the customer-facing renderer,
///   3. no customer mutation is reachable - at the event layer, not only in the
///      widget tree - while the customer storefront keeps all of them.

// Values a merchant owns but a customer must never see. Distinctive on purpose:
// if any of them reaches the rendered tree, the assertion names the leak.
const _privateCostPrice = 41.25;
const _privateStockQuantity = 137;
const _privateKeyword = 'private-merchant-keyword';
const _ownerAttachment = 'https://internal.example/owner-attachment.pdf';

// Owner-side display values. Deliberately unlike anything the public endpoint
// returns, so a rendered string identifies its own source.
const _ownerName = 'اسم المالك للمتجر';
const _ownerCategory = 'Owner-side category';
const _ownerAddress = 'Owner-side address';
const _ownerDescription = 'Owner-side description';

/// Records every call the storefront makes so a forbidden request is a test
/// failure rather than an unobserved side effect.
class _SpyStorefrontApi extends ApiService {
  final List<String> reads = [];
  final List<String> mutations = [];

  bool failDetails = false;
  List<BusinessProductApiModel> publicProducts = const [];
  List<BusinessReviewApiModel> publicReviews = const [];

  /// Holds the PUBLIC detail request open so the loading gate can be observed.
  Completer<BusinessDetailApiModel>? pendingDetails;

  /// Overrides the public detail payload when a test needs distinctive public
  /// facts to tell apart from owner-side ones.
  BusinessDetailApiModel Function(String businessId)? detailBuilder;

  @override
  Future<BusinessDetailApiModel> business({required String businessId}) async {
    reads.add('GET /businesses/$businessId');
    final pending = pendingDetails;
    if (pending != null) return pending.future;
    if (failDetails) throw StateError('public business offline');
    return detailBuilder?.call(businessId) ??
        catalogBusinessDetail(id: businessId);
  }

  @override
  Future<List<BusinessProductApiModel>> businessProducts({
    required String businessId,
    required String classification,
  }) async {
    reads.add('GET /businesses/$businessId/products?$classification');
    return publicProducts;
  }

  @override
  Future<List<BusinessReviewApiModel>> businessReviews({
    required String businessId,
  }) async {
    reads.add('GET /businesses/$businessId/reviews');
    return publicReviews;
  }

  @override
  Future<FavoriteStatusApiResponse> favoriteStatus({
    required String token,
    required String businessId,
  }) async {
    // Protected, customer-scoped read. Recorded as a mutation-class call
    // because the preview must not issue it at all.
    mutations.add('GET /favorites/businesses/$businessId/status');
    return const FavoriteStatusApiResponse(
      businessFavorited: false,
      productIds: <String>{},
    );
  }

  @override
  Future<BusinessProductApiModel> setProductLiked({
    required String token,
    required String businessId,
    required String productId,
    required bool liked,
  }) async {
    mutations.add('POST /businesses/$businessId/products/$productId/like');
    return publicProducts.first;
  }

  @override
  Future<BusinessReviewApiModel> submitBusinessReview({
    required String token,
    required String businessId,
    required int rating,
    required String comment,
  }) async {
    mutations.add('POST /businesses/$businessId/reviews');
    return BusinessReviewApiModel.fromJson(const {
      'id': '64d000000000000000000001',
      'rating': 5,
      'comment': 'c',
    });
  }

  /// The owner catalogue is merchant-private. Reaching it from the preview
  /// would be exactly the mistake this task exists to prevent.
  @override
  Future<List<OwnerProduct>> ownerProducts({required String token}) async {
    mutations.add('GET /businesses/me/products');
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

/// Serves the merchant shell. Its owner objects deliberately carry private
/// values so the preview's data boundary is exercised with real leak bait.
class _SpyMerchantApi extends ApiService {
  bool failOwnerBusiness = false;

  /// Holds the shell in its loading state. A pending future rather than a
  /// delay, so the test never depends on the clock.
  bool suspendOwnerBusiness = false;
  int ownerBusinessCalls = 0;

  @override
  Future<OwnerBusiness> ownerBusiness({required String token}) async {
    ownerBusinessCalls++;
    if (suspendOwnerBusiness) return Completer<OwnerBusiness>().future;
    if (failOwnerBusiness) throw StateError('owner business offline');
    return OwnerBusiness.fromJson(const {
      'id': '64b000000000000000000001',
      'name': _ownerName,
      'englishName': 'Owner-side english name',
      'category': _ownerCategory,
      'address': _ownerAddress,
      'description': _ownerDescription,
      'attachmentUrl': _ownerAttachment,
    });
  }

  @override
  Future<BusinessDashboardData> businessDashboard({
    required String token,
  }) async => BusinessDashboardData.fromJson(const {});

  @override
  Future<OwnerOrderList> ownerOrders({
    required String token,
    String? statusGroup,
    int page = 1,
    int limit = 20,
  }) async => OwnerOrderList.fromJson(const {});

  @override
  Future<List<OwnerProduct>> ownerProducts({required String token}) async =>
      const [];
}

/// A product exactly as the PUBLIC serializer would deliver it, parsed from a
/// payload polluted with owner-only keys. Parsing rather than constructing is
/// the point: it proves the public model drops the private keys instead of the
/// test simply declining to pass them.
BusinessProductApiModel _publicProductFromPollutedPayload() {
  return BusinessProductApiModel.fromJson(const {
    'id': '64c000000000000000000001',
    'name': 'منتج عام',
    'description': 'public description',
    'price': 25,
    'discountPercent': 0,
    'finalPrice': 25,
    'inStock': true,
    'hasVariants': false,
    'variants': <Map<String, dynamic>>[],
    'minPrice': 25,
    'maxPrice': 25,
    'minFinalPrice': 25,
    'maxFinalPrice': 25,
    'classification': 'new',
    'imageUrls': <String>[],
    // Owner-only keys, present in the payload and expected to be dropped.
    'costPrice': _privateCostPrice,
    'stockQuantity': _privateStockQuantity,
    'unlimitedStock': false,
    'keywords': <String>[_privateKeyword],
    'isActive': true,
  });
}

/// [closeOnTearDown] is false for widget tests: `BlocProvider` disposes the
/// bloc there, and awaiting `close()` inside `testWidgets` would wait on a
/// stream-controller completion that the faked clock never delivers.
/// A public detail with facts no seed could invent: a real public id and
/// non-zero counts. Anything asserted from these can only have come from the
/// public endpoint.
BusinessDetailApiModel _distinctPublicDetail(String id) {
  return BusinessDetailApiModel(
    id: id,
    publicId: 'MXB-0042',
    name: 'الاسم العام للمتجر',
    englishName: 'Public store name',
    category: 'Public category',
    description: 'Public description',
    address: 'Public address',
    products: const [],
    productCount: 7,
    rating: 4.5,
    ratingCount: 12,
    followerCount: 42,
    viewCount: 99,
    discount: null,
    colorValue: 0xffdeeef8,
  );
}

/// Starts the storefront without waiting for it to become ready.
///
/// Used where the PUBLIC detail request is deliberately still in flight, so
/// there is no ready state to await.
BusinessProfileBloc _startingBloc(
  _SpyStorefrontApi api, {
  required BusinessProfileViewMode viewMode,
}) {
  return BusinessProfileBloc(apiService: api, viewMode: viewMode)
    ..add(const BusinessProfileStarted('64b000000000000000000001'));
}

Future<BusinessProfileBloc> _startedBloc(
  _SpyStorefrontApi api, {
  required BusinessProfileViewMode viewMode,
  bool closeOnTearDown = true,
  ReviewEligibilityGateway? reviewEligibilityGateway,
}) async {
  final bloc = BusinessProfileBloc(
    apiService: api,
    viewMode: viewMode,
    reviewEligibilityGateway: reviewEligibilityGateway,
  );
  if (closeOnTearDown) addTearDown(bloc.close);

  final ready = bloc.stream.firstWhere(
    (state) => state.status == BusinessProfileStatus.ready,
  );
  bloc.add(const BusinessProfileStarted('64b000000000000000000001'));
  await ready;
  // The favourite-status read is fired after `ready` is emitted, so drain the
  // queue before asserting that it did or did not happen.
  await drainMicrotasks();

  return bloc;
}

/// Lets every already-scheduled continuation run.
///
/// Deliberately microtasks and not `Future.delayed`: inside `testWidgets` the
/// clock is faked, so a timer-based drain would wait for a pump that has not
/// happened yet and hang the test.
Future<void> drainMicrotasks({int turns = 20}) async {
  for (var turn = 0; turn < turns; turn++) {
    await Future<void>.value();
  }
}

/// The seed a customer arrives with: it came from the PUBLIC business list, so
/// customer mode may legitimately render it while the detail request resolves.
const _publicListSeed = HomeBusiness(
  id: '64b000000000000000000001',
  name: 'اسم من القائمة العامة',
  category: 'Public list category',
  products: [],
  rating: 0,
  colorValue: 0xffdeeef8,
);

Widget _storefront(
  BusinessProfileBloc bloc, {
  required BusinessProfileViewMode viewMode,
  HomeBusiness seed = _publicListSeed,
}) {
  return BusinessProfilePage(
    business: seed,
    onNavChanged: (_) {},
    viewMode: viewMode,
    bloc: bloc,
  );
}

/// Moves the storefront onto the products tab and settles the resulting load.
Future<void> _openProductsTab(WidgetTester tester) async {
  await tester.tap(find.text('المنتجات'));
  await settleFrames(tester);
}

/// Taps [finder] and lets the resulting frames run.
///
/// `pumpLocalized` lays the page out on a surface tall enough to hold it, so
/// the tap always lands on the real widget rather than missing off-screen.
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await settleFrames(tester);
}

Future<void> _openReviewsTab(WidgetTester tester) async {
  await tester.tap(find.text('التقييمات'));
  await settleFrames(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadAppTranslations);

  setUp(() {
    useAuthenticatedSession(business: true);
  });

  group('preview data source is the public contract', () {
    test(
      'C - preview products come from the public products endpoint',
      () async {
        final api = _SpyStorefrontApi()
          ..publicProducts = [_publicProductFromPollutedPayload()];
        final bloc = await _startedBloc(
          api,
          viewMode: BusinessProfileViewMode.merchantPreview,
        );

        expect(
          api.reads,
          containsAll([
            'GET /businesses/64b000000000000000000001',
            'GET /businesses/64b000000000000000000001/products?new',
          ]),
        );
        expect(bloc.state.products.single.name, 'منتج عام');
        // The owner catalogue is never consulted for what customers can see.
        expect(api.mutations, isEmpty);
      },
    );

    test(
      'D - a product the public endpoint withholds is never shown as customer-visible',
      () async {
        // The server decides visibility. An inactive product is simply absent
        // from the public response, and the preview has no second source that
        // could resurrect it.
        final api = _SpyStorefrontApi()..publicProducts = const [];
        final bloc = await _startedBloc(
          api,
          viewMode: BusinessProfileViewMode.merchantPreview,
        );

        expect(bloc.state.products, isEmpty);
        expect(api.mutations, isEmpty);
        expect(
          api.reads.where((call) => call.contains('/businesses/me')),
          isEmpty,
        );
      },
    );

    test(
      'H - opening the preview issues no customer-scoped protected read',
      () async {
        final api = _SpyStorefrontApi();
        await _startedBloc(
          api,
          viewMode: BusinessProfileViewMode.merchantPreview,
        );

        expect(api.mutations, isEmpty);
      },
    );

    test(
      'H (customer control) - the customer storefront still reads favourite status',
      () async {
        final api = _SpyStorefrontApi();
        await _startedBloc(api, viewMode: BusinessProfileViewMode.customer);

        expect(api.mutations, [
          'GET /favorites/businesses/64b000000000000000000001/status',
        ]);
      },
    );
  });

  group('preview is read only at the event layer', () {
    test('I - a like event in preview emits no like request', () async {
      final api = _SpyStorefrontApi()
        ..publicProducts = [_publicProductFromPollutedPayload()];
      final bloc = await _startedBloc(
        api,
        viewMode: BusinessProfileViewMode.merchantPreview,
      );

      bloc.add(
        const BusinessProfileProductLikeToggled('64c000000000000000000001'),
      );
      await drainMicrotasks();

      expect(api.mutations, isEmpty);
      expect(bloc.state.likedProductIds, isEmpty);
    });

    test('I (customer control) - a like event still reaches the API', () async {
      final api = _SpyStorefrontApi()
        ..publicProducts = [_publicProductFromPollutedPayload()];
      final bloc = await _startedBloc(
        api,
        viewMode: BusinessProfileViewMode.customer,
      );

      final liked = bloc.stream.firstWhere(
        (state) => state.likedProductIds.isNotEmpty,
      );
      bloc.add(
        const BusinessProfileProductLikeToggled('64c000000000000000000001'),
      );
      await liked;

      expect(
        api.mutations,
        contains(
          'POST /businesses/64b000000000000000000001/products/64c000000000000000000001/like',
        ),
      );
    });

    test('J - a review event in preview emits no review request', () async {
      final api = _SpyStorefrontApi();
      final bloc = await _startedBloc(
        api,
        viewMode: BusinessProfileViewMode.merchantPreview,
      );

      bloc.add(
        const BusinessProfileReviewSubmitted(rating: 5, comment: 'ممتاز'),
      );
      await drainMicrotasks();

      expect(api.mutations, isEmpty);
      // Not even a transient saving state: the event is refused, not attempted.
      expect(bloc.state.status, BusinessProfileStatus.ready);
      expect(bloc.state.reviews, isEmpty);
    });

    test(
      'J (customer control) - an eligible customer review reaches the API',
      () async {
        useAuthenticatedSession(business: false);

        final api = _SpyStorefrontApi();
        final bloc = await _startedBloc(
          api,
          viewMode: BusinessProfileViewMode.customer,
          reviewEligibilityGateway: _EligibleReviewGateway(),
        );

        final eligible = bloc.stream.firstWhere(
          (state) =>
              state.reviewEligibilityStatus == ReviewEligibilityStatus.eligible,
        );
        bloc.add(const BusinessProfileMainTabChanged(2));
        await eligible;

        final saved = bloc.stream.firstWhere(
          (state) =>
              state.status == BusinessProfileStatus.ready &&
              api.mutations.contains(
                'POST /businesses/64b000000000000000000001/reviews',
              ),
        );
        bloc.add(
          const BusinessProfileReviewSubmitted(rating: 5, comment: 'ممتاز'),
        );
        await saved;

        expect(
          api.mutations,
          contains('POST /businesses/64b000000000000000000001/reviews'),
        );
      },
    );
  });

  group('private merchant fields never reach the customer renderer', () {
    test('M/N/O - the public product model carries no owner-only field', () {
      final product = _publicProductFromPollutedPayload();

      // The polluted payload proves the drop happens at parse time. Anything
      // the renderer can reach is on this object, and none of it is private.
      final renderable = <Object?>[
        product.id,
        product.name,
        product.description,
        product.price,
        product.imageUrl,
        ...product.imageUrls,
        product.classification,
        product.rating,
        product.ratingCount,
        product.likeCount,
        product.isService,
      ].map((value) => value.toString()).toList();

      expect(renderable, isNot(contains(_privateCostPrice.toString())));
      expect(renderable, isNot(contains(_privateStockQuantity.toString())));
      expect(renderable, isNot(contains(_privateKeyword)));
    });

    test('the preview seed carries the trusted id and no display fact', () {
      final owner = OwnerBusiness.fromJson(const {
        'id': '64b000000000000000000001',
        'name': 'متجر التجربة',
        'englishName': 'Preview store',
        'category': 'Test category',
        'address': 'Test address',
        'description': 'Owner description',
        'attachmentUrl': _ownerAttachment,
        'logoUrl': 'https://internal.example/logo.png',
        'socialLinks': {'whatsapp': '+900000000'},
      });

      final seed = StorePreviewPage.identitySeed(owner);

      // The trusted id is the only thing the owner record is allowed to
      // answer: which business is mine.
      expect(seed.id, owner.id);

      // Nothing else survives - not the owner-only fields, and not even the
      // owner's copy of fields that also happen to be public. Whatever a
      // customer sees has to come from the public endpoint.
      final seedStrings = <String>[
        seed.name,
        seed.englishName,
        seed.category,
        seed.address,
        seed.description,
        seed.publicId,
        ...seed.products,
      ];
      expect(seedStrings, everyElement(isEmpty));
      expect(seedStrings, isNot(contains(_ownerAttachment)));
      expect(seed.followerCount, 0);
      expect(seed.productCount, 0);
      expect(seed.rating, 0);
    });

    testWidgets(
      'M/N/O - nothing private is rendered anywhere in the preview product grid',
      (tester) async {
        final api = _SpyStorefrontApi()
          ..publicProducts = [_publicProductFromPollutedPayload()];
        final bloc = await _startedBloc(
          api,
          viewMode: BusinessProfileViewMode.merchantPreview,
          closeOnTearDown: false,
        );

        await pumpLocalized(
          tester,
          _storefront(bloc, viewMode: BusinessProfileViewMode.merchantPreview),
        );
        await _openProductsTab(tester);

        final texts = renderedText(tester);
        for (final leak in <String>[
          _privateCostPrice.toString(),
          '41.25',
          _privateStockQuantity.toString(),
          _privateKeyword,
          _ownerAttachment,
        ]) {
          expect(
            texts.any((text) => text.contains(leak)),
            isFalse,
            reason: 'private value "$leak" was rendered in the preview',
          );
        }

        // The public truth is on screen, so the absence above is not an empty
        // screen passing by accident.
        expect(find.text('منتج عام'), findsOneWidget);
      },
    );
  });

  group('preview chrome and honest states', () {
    testWidgets('B - preview renders the real public store identity', (
      tester,
    ) async {
      final api = _SpyStorefrontApi();
      final bloc = await _startedBloc(
        api,
        viewMode: BusinessProfileViewMode.merchantPreview,
        closeOnTearDown: false,
      );

      await pumpLocalized(
        tester,
        _storefront(bloc, viewMode: BusinessProfileViewMode.merchantPreview),
      );

      // Name and public id come from the public detail fetch, not the seed.
      expect(find.text('Test business'), findsOneWidget);
      expect(find.text('ID: MXB-0001'), findsOneWidget);
      expect(find.text('وضع المعاينة - هذا ما يراه الزبون'), findsOneWidget);
      expect(find.text('إنهاء المعاينة'), findsOneWidget);
    });

    testWidgets('E - preview shows a loading state while the store resolves', (
      tester,
    ) async {
      final merchantApi = _SpyMerchantApi()..suspendOwnerBusiness = true;
      final bloc = BusinessBloc(apiService: merchantApi);
      bloc.add(const BusinessStarted());

      await pumpLocalized(
        tester,
        BlocProvider<BusinessBloc>.value(
          value: bloc,
          child: const StorePreviewPage(),
        ),
      );

      // Honest: a spinner while the owner business is still resolving, and no
      // storefront rendered from nothing.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(BusinessProfilePage), findsNothing);
      expect(find.text('معاينة المتجر'), findsOneWidget);
    });

    testWidgets('F - preview shows a truthful failure with a working retry', (
      tester,
    ) async {
      final merchantApi = _SpyMerchantApi()..failOwnerBusiness = true;
      final bloc = BusinessBloc(apiService: merchantApi);

      final failed = bloc.stream.firstWhere(
        (state) => state.status == BusinessStatus.failure,
      );
      bloc.add(const BusinessStarted());
      await failed;

      await pumpLocalized(
        tester,
        BlocProvider<BusinessBloc>.value(
          value: bloc,
          child: const StorePreviewPage(),
        ),
      );

      expect(find.text('إعادة المحاولة'), findsOneWidget);
      expect(merchantApi.ownerBusinessCalls, 1);

      await tester.tap(find.text('إعادة المحاولة'));
      await settleFrames(tester);

      expect(merchantApi.ownerBusinessCalls, 2);
    });

    testWidgets('G - preview shows an honest empty products state', (
      tester,
    ) async {
      final api = _SpyStorefrontApi()..publicProducts = const [];
      final bloc = await _startedBloc(
        api,
        viewMode: BusinessProfileViewMode.merchantPreview,
        closeOnTearDown: false,
      );

      await pumpLocalized(
        tester,
        _storefront(bloc, viewMode: BusinessProfileViewMode.merchantPreview),
      );
      await _openProductsTab(tester);

      // The catalogue's own empty copy, not an invented placeholder product.
      expect(find.byType(GridView), findsNothing);
      expect(find.text('منتج عام'), findsNothing);
    });

    testWidgets('G - preview shows an honest empty reviews state', (
      tester,
    ) async {
      final api = _SpyStorefrontApi()..publicReviews = const [];
      final bloc = await _startedBloc(
        api,
        viewMode: BusinessProfileViewMode.merchantPreview,
        closeOnTearDown: false,
      );

      await pumpLocalized(
        tester,
        _storefront(bloc, viewMode: BusinessProfileViewMode.merchantPreview),
      );
      await _openReviewsTab(tester);

      expect(find.text('كل التقييمات'), findsOneWidget);
      expect(bloc.state.reviews, isEmpty);
    });
  });

  group('preview removes every customer mutation affordance', () {
    testWidgets('K - no customer chat affordance with the merchant own store', (
      tester,
    ) async {
      final api = _SpyStorefrontApi();
      final bloc = await _startedBloc(
        api,
        viewMode: BusinessProfileViewMode.merchantPreview,
        closeOnTearDown: false,
      );

      await pumpLocalized(
        tester,
        _storefront(bloc, viewMode: BusinessProfileViewMode.merchantPreview),
      );

      expect(
        find.widgetWithIcon(IconButton, Icons.chat_bubble_outline_rounded),
        findsNothing,
        reason: 'the preview must not offer a chat with its own store',
      );
    });

    testWidgets('L - the add-to-cart action cannot be triggered from preview', (
      tester,
    ) async {
      final api = _SpyStorefrontApi()
        ..publicProducts = [_publicProductFromPollutedPayload()];
      final bloc = await _startedBloc(
        api,
        viewMode: BusinessProfileViewMode.merchantPreview,
        closeOnTearDown: false,
      );

      await pumpLocalized(
        tester,
        _storefront(bloc, viewMode: BusinessProfileViewMode.merchantPreview),
      );
      await _openProductsTab(tester);

      final cartButton = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('أضف إلى السلة'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(cartButton.onPressed, isNull);

      // The card itself must not open the interactive product page either.
      // Scrolled into view first, so this is a real tap that lands on the card.
      await _tapVisible(tester, find.text('منتج عام'));
      expect(find.byType(ProductDetailsPage), findsNothing);
    });

    testWidgets('J - the review composer is absent from preview', (
      tester,
    ) async {
      final api = _SpyStorefrontApi();
      final bloc = await _startedBloc(
        api,
        viewMode: BusinessProfileViewMode.merchantPreview,
        closeOnTearDown: false,
      );

      await pumpLocalized(
        tester,
        _storefront(bloc, viewMode: BusinessProfileViewMode.merchantPreview),
      );
      await _openReviewsTab(tester);

      expect(find.text('نشر'), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('I - the product like control is absent from preview', (
      tester,
    ) async {
      final api = _SpyStorefrontApi()
        ..publicProducts = [_publicProductFromPollutedPayload()];
      final bloc = await _startedBloc(
        api,
        viewMode: BusinessProfileViewMode.merchantPreview,
        closeOnTearDown: false,
      );

      await pumpLocalized(
        tester,
        _storefront(bloc, viewMode: BusinessProfileViewMode.merchantPreview),
      );
      await _openProductsTab(tester);

      expect(
        find.descendant(
          of: find.byType(GridView),
          matching: find.byIcon(Icons.favorite_border_rounded),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(GridView),
          matching: find.byIcon(Icons.favorite_rounded),
        ),
        findsNothing,
      );
    });
  });

  group('customer storefront regression', () {
    testWidgets('P - the customer storefront keeps every mutation affordance', (
      tester,
    ) async {
      useAuthenticatedSession(business: false);

      final api = _SpyStorefrontApi()
        ..publicProducts = [_publicProductFromPollutedPayload()];
      final bloc = await _startedBloc(
        api,
        viewMode: BusinessProfileViewMode.customer,
        closeOnTearDown: false,
        reviewEligibilityGateway: _EligibleReviewGateway(),
      );

      await pumpLocalized(
        tester,
        _storefront(bloc, viewMode: BusinessProfileViewMode.customer),
      );

      // Scoped to the button: the customer bottom navigation carries a chat
      // glyph of its own, which is not the affordance under test.
      expect(
        find.widgetWithIcon(IconButton, Icons.chat_bubble_outline_rounded),
        findsOneWidget,
      );

      await _openProductsTab(tester);
      // Scoped to the grid: the customer bottom navigation carries a favourite
      // icon of its own, which is not the control under test.
      expect(
        find.descendant(
          of: find.byType(GridView),
          matching: find.byIcon(Icons.favorite_border_rounded),
        ),
        findsOneWidget,
      );
      final cartButton = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('أضف إلى السلة'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(cartButton.onPressed, isNotNull);

      await _openReviewsTab(tester);
      expect(find.text('نشر'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets(
      'Q - customer product navigation still opens the product page',
      (tester) async {
        final api = _SpyStorefrontApi()
          ..publicProducts = [_publicProductFromPollutedPayload()];
        final bloc = await _startedBloc(
          api,
          viewMode: BusinessProfileViewMode.customer,
          closeOnTearDown: false,
        );

        await pumpLocalized(
          tester,
          _storefront(bloc, viewMode: BusinessProfileViewMode.customer),
        );
        await _openProductsTab(tester);

        await tester.tap(find.text('منتج عام'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byType(ProductDetailsPage), findsOneWidget);
      },
    );

    testWidgets('P - product filters still switch in customer mode', (
      tester,
    ) async {
      final api = _SpyStorefrontApi()
        ..publicProducts = [_publicProductFromPollutedPayload()];
      final bloc = await _startedBloc(
        api,
        viewMode: BusinessProfileViewMode.customer,
        closeOnTearDown: false,
      );

      await pumpLocalized(
        tester,
        _storefront(bloc, viewMode: BusinessProfileViewMode.customer),
      );
      await _openProductsTab(tester);

      await tester.tap(find.text('عروض'));
      await settleFrames(tester);

      expect(bloc.state.productClassification, 'offers');
    });
  });

  group('merchant shell entry point', () {
    testWidgets(
      'A/R - the profile tab offers preview beside the existing actions',
      (tester) async {
        final merchantApi = _SpyMerchantApi();
        final bloc = BusinessBloc(apiService: merchantApi);

        final ready = bloc.stream.firstWhere(
          (state) => state.status == BusinessStatus.ready,
        );
        bloc.add(const BusinessStarted());
        await ready;

        await pumpLocalized(
          tester,
          BlocProvider<BusinessBloc>.value(
            value: bloc,
            child: BusinessShellPage(onLoggedOut: () {}),
          ),
        );

        // R - shell navigation still moves between tabs.
        bloc.add(const BusinessTabChanged(4));
        await settleFrames(tester);

        expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
        // Nothing existing was displaced to make room for it.
        expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
        expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
        expect(find.byIcon(Icons.logout_rounded), findsOneWidget);
      },
    );
  });

  group('R1 - the preview shows nothing until public truth arrives', () {
    /// Boots the merchant shell so the owner business is resolved, exactly as
    /// it is when a merchant opens the preview for real.
    Future<BusinessBloc> resolvedMerchantSession(_SpyMerchantApi api) async {
      final bloc = BusinessBloc(apiService: api);
      final ready = bloc.stream.firstWhere(
        (state) => state.status == BusinessStatus.ready,
      );
      bloc.add(const BusinessStarted());
      await ready;
      return bloc;
    }

    Widget previewPage(BusinessBloc merchant, BusinessProfileBloc storefront) {
      return BlocProvider<BusinessBloc>.value(
        value: merchant,
        child: StorePreviewPage(storefrontBloc: storefront),
      );
    }

    /// Fails if any owner-side display fact reached the screen.
    void expectNoOwnerFactRendered(WidgetTester tester) {
      final texts = renderedText(tester);
      for (final ownerFact in [
        _ownerName,
        _ownerCategory,
        _ownerAddress,
        _ownerDescription,
        _ownerAttachment,
      ]) {
        expect(
          texts.any((text) => text.contains(ownerFact)),
          isFalse,
          reason: 'owner value "$ownerFact" was rendered as customer truth',
        );
      }
    }

    /// Fails if any storefront display fact reached the screen - including the
    /// zeroes a seed would supply, which would be manufactured facts.
    void expectNoStorefrontBody(WidgetTester tester) {
      final texts = renderedText(tester);

      expect(
        texts.any((text) => text.startsWith('ID:')),
        isFalse,
        reason: 'a public id was shown before public details resolved',
      );
      for (final count in ['0 متابع', '0 منتج', '42 متابع', '7 منتج']) {
        expect(texts, isNot(contains(count)), reason: count);
      }
      expect(find.byType(GridView), findsNothing);
      // The tabs belong to the storefront body; their absence is what
      // distinguishes the gate from a merely empty storefront.
      expect(find.text('عن المتجر'), findsNothing);
      expect(find.text('المنتجات'), findsNothing);
      expect(find.text('التقييمات'), findsNothing);
    }

    testWidgets('A - a pending public detail renders loading, not the seed', (
      tester,
    ) async {
      final merchant = await resolvedMerchantSession(_SpyMerchantApi());

      final api = _SpyStorefrontApi()
        ..pendingDetails = Completer<BusinessDetailApiModel>()
        ..detailBuilder = _distinctPublicDetail
        // Products resolve while the detail request is still open, so this also
        // proves a half-loaded storefront cannot slip through.
        ..publicProducts = [_publicProductFromPollutedPayload()];
      final storefront = _startingBloc(
        api,
        viewMode: BusinessProfileViewMode.merchantPreview,
      );

      await pumpLocalized(tester, previewPage(merchant, storefront));

      // The storefront widget IS mounted - so it is the gate suppressing the
      // body, not an absent page.
      expect(find.byType(BusinessProfilePage), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expectNoOwnerFactRendered(tester);
      expectNoStorefrontBody(tester);
      expect(api.mutations, isEmpty);
    });

    testWidgets('B - a failed public detail renders failure, not the seed', (
      tester,
    ) async {
      final merchant = await resolvedMerchantSession(_SpyMerchantApi());

      final api = _SpyStorefrontApi()
        ..failDetails = true
        ..publicProducts = [_publicProductFromPollutedPayload()];
      final storefront = _startingBloc(
        api,
        viewMode: BusinessProfileViewMode.merchantPreview,
      );

      await pumpLocalized(tester, previewPage(merchant, storefront));

      expect(find.byType(BusinessProfilePage), findsOneWidget);
      expect(find.text('إعادة المحاولة'), findsOneWidget);
      expectNoOwnerFactRendered(tester);
      expectNoStorefrontBody(tester);
      expect(api.mutations, isEmpty);
    });

    testWidgets('C - retry refetches the public detail and then shows it', (
      tester,
    ) async {
      final merchant = await resolvedMerchantSession(_SpyMerchantApi());

      final api = _SpyStorefrontApi()..failDetails = true;
      final storefront = _startingBloc(
        api,
        viewMode: BusinessProfileViewMode.merchantPreview,
      );

      await pumpLocalized(tester, previewPage(merchant, storefront));
      expect(find.text('إعادة المحاولة'), findsOneWidget);

      final detailReadsBefore = api.reads
          .where((call) => call == 'GET /businesses/64b000000000000000000001')
          .length;

      api
        ..failDetails = false
        ..detailBuilder = _distinctPublicDetail;

      await _tapVisible(tester, find.text('إعادة المحاولة'));

      // The PUBLIC detail endpoint is what gets retried; the owner lookup is
      // not re-run, because it never failed.
      expect(
        api.reads
            .where((call) => call == 'GET /businesses/64b000000000000000000001')
            .length,
        detailReadsBefore + 1,
      );

      // Facts no seed could have invented.
      expect(find.text('الاسم العام للمتجر'), findsOneWidget);
      expect(find.text('ID: MXB-0042'), findsOneWidget);
      expect(find.text('42 متابع'), findsOneWidget);
      expect(find.text('7 منتج'), findsOneWidget);
      expectNoOwnerFactRendered(tester);
      expect(api.mutations, isEmpty);
    });

    testWidgets('D - customer mode still renders its public-list seed', (
      tester,
    ) async {
      final api = _SpyStorefrontApi()
        ..pendingDetails = Completer<BusinessDetailApiModel>()
        ..detailBuilder = _distinctPublicDetail;
      final storefront = _startingBloc(
        api,
        viewMode: BusinessProfileViewMode.customer,
      );

      await pumpLocalized(
        tester,
        _storefront(storefront, viewMode: BusinessProfileViewMode.customer),
      );

      // The gate is preview-only: the customer seed came from the public list,
      // so it stays on screen while the detail request resolves.
      expect(find.text('اسم من القائمة العامة'), findsOneWidget);
      expect(find.text('المنتجات'), findsOneWidget);
      expect(
        find.widgetWithIcon(IconButton, Icons.chat_bubble_outline_rounded),
        findsOneWidget,
      );

      // And it is replaced by the detail the moment that resolves.
      api.pendingDetails!.complete(
        _distinctPublicDetail('64b000000000000000000001'),
      );
      await settleFrames(tester);

      expect(find.text('الاسم العام للمتجر'), findsOneWidget);
      expect(find.text('اسم من القائمة العامة'), findsNothing);
    });
  });

  group('preview labels are localized', () {
    // The widget tests above render Arabic, so this closes the other half:
    // every preview key the code asks for exists in BOTH catalogues.
    const usedKeys = [
      'merchantPreview.title',
      'merchantPreview.open',
      'merchantPreview.banner',
      'merchantPreview.close',
      'merchantPreview.loadError',
      'merchantPreview.retry',
    ];

    for (final language in ['ar', 'en']) {
      test('$language defines every merchantPreview key', () async {
        final catalogue =
            jsonDecode(
                  await File(
                    'assets/translations/$language.json',
                  ).readAsString(),
                )
                as Map<String, dynamic>;
        final preview = catalogue['merchantPreview'] as Map<String, dynamic>?;

        expect(preview, isNotNull, reason: '$language has no merchantPreview');

        for (final key in usedKeys) {
          final leaf = key.split('.').last;
          expect(preview![leaf], isA<String>(), reason: '$language: $key');
          expect(
            (preview[leaf] as String).trim(),
            isNotEmpty,
            reason: '$language: $key is blank',
          );
        }
      });
    }
  });

  group('route authorization for /business/preview', () {
    const route = '/business/preview';

    test('S - a guest is sent to the business login flow', () {
      expect(
        AuthRouteGuard.redirect(
          uri: Uri.parse(route),
          session: const AuthSessionSnapshot(
            type: AuthSessionType.unauthenticated,
          ),
        ),
        '/business/login',
      );
    });

    test('T - an authenticated customer is sent to enrollment', () {
      expect(
        AuthRouteGuard.redirect(
          uri: Uri.parse(route),
          session: const AuthSessionSnapshot(
            type: AuthSessionType.customer,
            token: 'customer-token',
          ),
        ),
        '/business/enroll',
      );
    });

    test('U - an authenticated business is allowed through', () {
      expect(
        AuthRouteGuard.redirect(
          uri: Uri.parse(route),
          session: const AuthSessionSnapshot(
            type: AuthSessionType.business,
            token: 'merchant-token',
          ),
        ),
        isNull,
      );
    });

    test('a query parameter cannot claim the business role', () {
      for (final claim in [
        '$route?business=true',
        '$route?owner=true',
        '$route?preview=true',
        '$route?businessId=64b000000000000000000009',
      ]) {
        expect(
          AuthRouteGuard.redirect(
            uri: Uri.parse(claim),
            session: const AuthSessionSnapshot(
              type: AuthSessionType.customer,
              token: 'customer-token',
            ),
          ),
          '/business/enroll',
          reason: claim,
        );
      }
    });
  });
}
