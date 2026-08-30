// MERZOX-UI-GOLDEN-I4-I1 - the five deterministic seed goldens.
//
// These are Flutter rendering baselines captured on the canonical Windows
// golden environment. They are NOT evidence of Adobe XD parity: nothing here
// compares a Merzox screen against an XD reference, and no production widget is
// adjusted to make a capture look "right".
//
// Every fixture below is feature specific and therefore lives here rather than
// in `merzox_golden_harness.dart`. The construction strategies are the ones the
// existing suite already proves:
//
//   * `test/widget_test.dart`          - Arabic `EasyLocalization` pump, the
//                                        `OnboardingBloc` + `SharedPreferences`
//                                        mock setup, and the
//                                        `ApiService`-subclass fake used to
//                                        keep `AuthBloc` off the network.
//   * `test/merchant_store_preview_test.dart`
//                                      - the merchant/storefront fake API pair,
//                                        the `BusinessStarted` /
//                                        `BusinessProfileStarted` await-ready
//                                        wiring, and the `storefrontBloc` seam
//                                        on `StorePreviewPage`.

import 'dart:async';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/about_us/bloc/about_us_bloc.dart';
import 'package:merzox/features/about_us/bloc/about_us_event.dart';
import 'package:merzox/features/about_us/bloc/about_us_state.dart';
import 'package:merzox/features/about_us/pages/about_us_page.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/authentication/pages/login_page.dart';
import 'package:merzox/features/authentication/pages/signup_page.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/features/business/preview/store_preview_page.dart';
import 'package:merzox/features/business/shell/business_bloc.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_bloc.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_event.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_state.dart';
import 'package:merzox/features/business_profile/business_profile_view_mode.dart';
import 'package:merzox/features/favorites/bloc/favorites_bloc.dart';
import 'package:merzox/features/favorites/bloc/favorites_event.dart';
import 'package:merzox/features/favorites/bloc/favorites_state.dart';
import 'package:merzox/features/favorites/pages/favorites_page.dart';
import 'package:merzox/features/home/home_screen.dart';
import 'package:merzox/features/home/presentation/bloc/home_bloc.dart';
import 'package:merzox/features/home/presentation/bloc/home_event.dart';
import 'package:merzox/features/home/presentation/bloc/home_state_.dart';
import 'package:merzox/features/onboarding/bloc/onboarding_bloc.dart';
import 'package:merzox/features/onboarding/view/onboarding_screen.dart';
import 'package:merzox/features/orders/bloc/order_tracking_bloc.dart';
import 'package:merzox/features/orders/bloc/order_tracking_event.dart';
import 'package:merzox/features/orders/bloc/order_tracking_state.dart';
import 'package:merzox/features/orders/pages/order_tracking_page.dart';
import 'package:merzox/features/splash/presentation/splash_screen.dart';
import 'package:merzox/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'merzox_golden_harness.dart';

// ---------------------------------------------------------------------------
// Login fixture
// ---------------------------------------------------------------------------

/// An [ApiService] that cannot reach the network.
///
/// The idle authentication goldens never submit a form, so any call here
/// means a capture drifted into a request-driven state and the test should say so
/// rather than quietly hit a real endpoint.
final class _OfflineAuthApiService extends ApiService {
  @override
  Future<AuthApiResponse> login({
    required String identifier,
    required String password,
  }) async {
    throw StateError('an idle authentication golden must not call login()');
  }

  @override
  Future<SignupApiResponse> signup({
    required String name,
    String? email,
    String? phone,
    required String password,
    required String userType,
    String address = '',
    String gender = 'unspecified',
  }) async {
    throw StateError('an idle authentication golden must not call signup()');
  }
}

// ---------------------------------------------------------------------------
// Home shell fixture
// ---------------------------------------------------------------------------

/// An [ApiService] the home shell cannot reach the network through.
///
/// The guest cart seed never dispatches `HomeStarted`, so no catalog request
/// belongs to this capture. A call here means the fixture drifted into a
/// data-driven state and the test should say so rather than reach a real
/// endpoint.
final class _OfflineHomeApiService extends ApiService {
  @override
  Future<BusinessListApiResponse> businesses({
    int page = 1,
    int limit = 100,
    String? search,
    String? sort,
    bool? discounted,
    double? latitude,
    double? longitude,
    int? radiusMeters,
  }) async {
    throw StateError('the guest cart golden must not call businesses()');
  }
}

// ---------------------------------------------------------------------------
// Favorites fixture
// ---------------------------------------------------------------------------

/// One liked product, repeated four times as the artboard's 2x2 grid shows.
///
/// `imageUrl` is deliberately blank. The artboard puts a photograph in each
/// card; a golden must not fetch one, so the card reaches its placeholder
/// branch instead. That difference is real and is recorded in the mapping's
/// semantic reason rather than hidden.
Map<String, dynamic> _seedFavoriteProduct(int index) {
  return <String, dynamic>{
    'business': <String, dynamic>{
      'id': '64b00000000000000000001$index',
      'publicId': '002010$index',
      'name': 'متجر الياسمين',
      'category': 'أفضل المتاجر',
    },
    'product': <String, dynamic>{
      'id': '64c00000000000000000001$index',
      'name': index.isEven ? 'أساس فت مي' : 'بودرة نوت',
      'description': '',
      'price': index.isEven ? 65 : 40,
      'discountPercent': 0,
      'finalPrice': index.isEven ? 65 : 40,
      'inStock': true,
      'imageUrl': '',
      'imageUrls': <String>[],
      'classification': 'new',
      'rating': 4,
      'ratingCount': 12,
      'likeCount': 3,
      'isService': false,
      // The product contract refuses to default these. A simple product must
      // still expose complete price bounds - they collapse onto its single
      // price - because a missing bound would otherwise be inferred here.
      'hasVariants': false,
      'variants': <Map<String, dynamic>>[],
      'minPrice': index.isEven ? 65 : 40,
      'maxPrice': index.isEven ? 65 : 40,
      'minFinalPrice': index.isEven ? 65 : 40,
      'maxFinalPrice': index.isEven ? 65 : 40,
    },
    'favoritedAt': '2022-02-15T14:40:00.000',
  };
}

final class _SeedFavoritesApi extends ApiService {
  @override
  Future<FavoriteProductListApiResponse> favoriteProducts({
    required String token,
    int page = 1,
    int limit = 20,
  }) async {
    return FavoriteProductListApiResponse.fromJson(<String, dynamic>{
      'products': <Map<String, dynamic>>[
        for (int index = 0; index < 4; index++) _seedFavoriteProduct(index),
      ],
      'pagination': <String, dynamic>{
        'page': 1,
        'total': 4,
        'hasMore': false,
      },
    });
  }

  @override
  Future<FavoriteBusinessListApiResponse> favoriteBusinesses({
    required String token,
    int page = 1,
    int limit = 20,
  }) async {
    return FavoriteBusinessListApiResponse.fromJson(const <String, dynamic>{
      'businesses': <Map<String, dynamic>>[],
      'pagination': <String, dynamic>{'page': 1, 'total': 0, 'hasMore': false},
    });
  }
}

// ---------------------------------------------------------------------------
// About Us fixture
// ---------------------------------------------------------------------------

/// The `من نحن` page is server-driven, so its seed serves the payload the
/// artboard draws: the wordmark line, one introduction paragraph and the three
/// collapsed sections. Nothing is expanded - the artboard shows all three shut.
final class _SeedAboutUsApi extends ApiService {
  @override
  Future<AboutUsApiModel> aboutUs({required String languageCode}) async {
    return AboutUsApiModel.fromJson(<String, dynamic>{
      'pageTitle': 'من نحن',
      'appLabel': 'تطبيق',
      'appName': 'MERZOX',
      'introduction':
          'نص افتراضي نص افتراضي نص افتراضي نص افتراضي نص افتراضي نص افتراضي '
          'نص افتراضي نص افتراضي نص افتراضي نص افتراضي نص افتراضي نص افتراضي '
          'نص افتراضي',
      'sections': <Map<String, dynamic>>[
        <String, dynamic>{
          'key': 'how',
          'title': 'آلية العمل',
          'content': 'نص افتراضي',
        },
        <String, dynamic>{
          'key': 'terms',
          'title': 'شروط العمل',
          'content': 'نص افتراضي',
        },
        <String, dynamic>{
          'key': 'rules',
          'title': 'أحكام العمل',
          'content': 'نص افتراضي',
        },
      ],
      'updatedAt': null,
    });
  }
}

// ---------------------------------------------------------------------------
// Order tracking fixture
// ---------------------------------------------------------------------------

const String _trackedOrderId = '64d000000000000000000001';

/// The order the `تتبع الطلب` artboard draws: placed, nothing further reached.
///
/// Every tracking field is spelled out because `OrderTrackingApiModel` refuses
/// to default them - a permission the server never sent must never be
/// synthesized here. No courier is assigned and no courier location exists, so
/// the live map and its network tiles are not part of this capture.
final class _SeedOrderTrackingApi extends ApiService {
  @override
  Future<OrderApiModel> order({
    required String token,
    required String orderId,
  }) async {
    return OrderApiModel.fromJson(<String, dynamic>{
      'id': orderId,
      'publicId': '222321',
      'business': <String, dynamic>{
        'id': '64b000000000000000000009',
        'name': 'متجر الياسمين',
      },
      'items': <Map<String, dynamic>>[],
      'subtotal': 120,
      'deliveryFee': 10,
      'total': 130,
      'currency': 'ILS',
      'deliveryAddress': 'عنوان التوصيل للاختبار',
      'paymentMethod': 'cash',
      'status': 'pending',
      'statusGroup': 'current',
      'statusHistory': <Map<String, dynamic>>[],
      'cancellationReason': '',
      // The artboard's own stamp: Saturday 15.2.2022, 02:40 PM.
      'createdAt': '2022-02-15T14:40:00.000',
      'courier': <String, dynamic>{},
      'tracking': <String, dynamic>{
        'isCancelled': false,
        'currentStep': 'placed',
        'currentIndex': 0,
        'steps': <Map<String, dynamic>>[
          <String, dynamic>{
            'step': 'placed',
            'reachedAt': '2022-02-15T14:40:00.000',
            'isReached': true,
          },
          <String, dynamic>{
            'step': 'preparing',
            'reachedAt': null,
            'isReached': false,
          },
          <String, dynamic>{
            'step': 'outForDelivery',
            'reachedAt': null,
            'isReached': false,
          },
          <String, dynamic>{
            'step': 'delivered',
            'reachedAt': null,
            'isReached': false,
          },
        ],
        'courier': <String, dynamic>{},
        'courierLocation': null,
        'canCancel': true,
        'canChangeAddress': true,
        'canReview': false,
      },
    });
  }
}

/// Installs the authenticated customer session the tracking bloc reads.
void _useAuthenticatedCustomerSession() {
  SharedPreferences.setMockInitialValues(<String, Object>{
    AuthBloc.sessionKey: true,
    AuthBloc.tokenKey: 'seed-golden-token',
    AuthBloc.userTypeKey: 'customer',
  });
}

// ---------------------------------------------------------------------------
// Store preview fixtures
// ---------------------------------------------------------------------------

const String _previewBusinessId = '64b000000000000000000001';

/// Serves the merchant shell so the preview can resolve *which* business is
/// being previewed. Only the four reads `BusinessBloc` performs on start are
/// answered; anything else would be an unexpected request.
final class _SeedMerchantApi extends ApiService {
  @override
  Future<OwnerBusiness> ownerBusiness({required String token}) async {
    return OwnerBusiness.fromJson(const <String, dynamic>{
      'id': _previewBusinessId,
      'name': 'اسم المالك للمتجر',
      'englishName': 'Owner side name',
      'category': 'Owner side category',
      'address': 'Owner side address',
      'description': 'Owner side description',
      // Deliberately blank: the preview must not need a remote logo to render.
      'logoUrl': '',
      'attachmentUrl': '',
    });
  }

  @override
  Future<BusinessDashboardData> businessDashboard({
    required String token,
  }) async => BusinessDashboardData.fromJson(const <String, dynamic>{});

  @override
  Future<OwnerOrderList> ownerOrders({
    required String token,
    String? statusGroup,
    int page = 1,
    int limit = 20,
  }) async => OwnerOrderList.fromJson(const <String, dynamic>{});

  @override
  Future<List<OwnerProduct>> ownerProducts({required String token}) async =>
      const <OwnerProduct>[];
}

/// The single service the Store Preview artboard shows under "About".
///
/// Deterministic and entirely local: no image URL, so the About tab renders its
/// icon placeholder instead of reaching `Image.network`. Rendering it triggers
/// no customer mutation - the About tab draws services as plain, tapless tiles.
const BusinessProductApiModel _seedService = BusinessProductApiModel(
  id: '64c000000000000000000001',
  name: 'مكياج',
  description: '',
  price: 0,
  imageUrl: '',
  imageUrls: <String>[],
  classification: 'new',
  rating: 0,
  ratingCount: 0,
  likeCount: 0,
  isService: true,
);

/// Serves the PUBLIC storefront contracts the preview reads.
///
/// Every payload is chosen so the loaded storefront renders from local
/// resources only: no product carries an image URL, there are no reviews, and
/// the business has no remote logo. `BusinessProfilePage` therefore reaches its
/// placeholder branches instead of `Image.network`, and the golden needs no
/// successful HTTP.
final class _SeedStorefrontApi extends ApiService {
  @override
  Future<BusinessDetailApiModel> business({required String businessId}) async {
    return BusinessDetailApiModel(
      id: businessId,
      publicId: '0020101',
      name: 'متجر الياسمين',
      englishName: 'Merzox demo store',
      category: 'أفضل المتاجر',
      description:
          'هذا النص افتراضي ، هذا النص افتراضي ، هذا النص افتراضي ، هذا النص '
          'افتراضي ، هذا النص افتراضي هذا النص افتراضي ، هذا النص افتراضي ، '
          'هذا النص افتراضي ، هذا النص افتراضي ، هذا النص افتراضي',
      address: '',
      // The About tab draws its services from the DETAIL payload, so the one
      // service the artboard shows lives here rather than in
      // `businessProducts`, which drives the Products tab.
      products: const <BusinessProductApiModel>[_seedService],
      productCount: 200,
      rating: 4.5,
      ratingCount: 12,
      followerCount: 300,
      viewCount: 99,
      discount: null,
      colorValue: 0xffdeeef8,
    );
  }

  @override
  Future<List<BusinessProductApiModel>> businessProducts({
    required String businessId,
    required String classification,
  }) async => const <BusinessProductApiModel>[];

  @override
  Future<List<BusinessReviewApiModel>> businessReviews({
    required String businessId,
  }) async => const <BusinessReviewApiModel>[];
}

/// Installs the authenticated merchant session `BusinessBloc` resolves its
/// token from. Mirrors `test/auth_session_fixtures.dart`, kept local so the
/// golden owns its own preconditions.
void _useAuthenticatedMerchantSession() {
  SharedPreferences.setMockInitialValues(<String, Object>{
    AuthBloc.sessionKey: true,
    AuthBloc.tokenKey: 'seed-golden-token',
    AuthBloc.userTypeKey: 'business',
  });
}

/// Closes [bloc] without awaiting it.
///
/// `merchant_store_preview_test.dart` records why: awaiting `close()` from
/// inside `testWidgets` waits on a stream-controller completion the faked clock
/// never delivers. Dropping the future still tears the bloc down.
void _closeOnTearDown<S>(BlocBase<S> bloc) {
  addTearDown(() => unawaited(bloc.close()));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(
    'MERZOX seed goldens - Arabic, 375x812, Windows canonical',
    () {
      setUpAll(() async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        await EasyLocalization.ensureInitialized();
        await loadMerzoxGoldenDateSymbols();
        await loadMerzoxGoldenFonts();
      });

      tearDown(() {
        SharedPreferences.setMockInitialValues(<String, Object>{});
      });

      // -- 1. Splash ------------------------------------------------------
      //
      // `lib/features/splash/presentation/pages/splash_page.dart` is commented
      // out in full and exports no `SplashPage` type, so the current stable
      // page-level splash representation is `SplashScreen`. It is instantiated
      // as shipped; nothing about it is adjusted for the capture.
      testWidgets('splash renders its Arabic seed baseline', (
        WidgetTester tester,
      ) async {
        await pumpMerzoxGoldenPage(tester, const SplashScreen());

        await expectMerzoxSeedGolden('splash_page_ar_375x812.png');

        // The capture above is the pre-navigation splash: the production 3s
        // timer has not fired, so no timer-driven navigation is part of this
        // golden. It is drained here only so the test leaves no pending timer
        // behind.
        await tester.pump(const Duration(seconds: 3, milliseconds: 100));
        await settleMerzoxGoldenFrames(tester);
      });

      // -- 2. Onboarding, initial page ------------------------------------
      testWidgets('onboarding renders its Arabic initial-state baseline', (
        WidgetTester tester,
      ) async {
        // Same mock-preferences setup `test/widget_test.dart` uses: the bloc
        // reads and writes `onboarding_completed`, and nothing may touch real
        // machine preferences.
        SharedPreferences.setMockInitialValues(<String, Object>{});

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<OnboardingBloc>(
            // `BlocProvider` owns and disposes the bloc, exactly as the
            // existing onboarding widget tests do.
            create: (_) => OnboardingBloc(),
            child: withMerzoxGoldenDeviceInsets(
              OnboardingScreen(onFinished: () {}),
            ),
          ),
        );

        // The seed is the first page only: no swipe, no skip, no completion.
        // These are the same Arabic labels the existing onboarding widget test
        // asserts for the initial state.
        expect(find.text('أفضل الخصومات'), findsOneWidget);
        expect(find.text('تخطي'), findsOneWidget);

        await expectMerzoxSeedGolden('onboarding_initial_ar_375x812.png');
      });

      // -- 3. Login, idle customer state ----------------------------------
      testWidgets('login renders its Arabic idle-state baseline', (
        WidgetTester tester,
      ) async {
        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<AuthBloc>(
            create: (_) => AuthBloc(apiService: _OfflineAuthApiService()),
            child: withMerzoxGoldenDeviceInsets(
              LoginPage(
                onAuthenticated: () {},
                onBrowseAsGuest: () {},
                onSignupRequested: () {},
                onForgotPasswordRequested: () {},
                businessMode: false,
              ),
            ),
          ),
        );

        await expectMerzoxSeedGolden('login_idle_ar_375x812.png');
      });

      // -- 4. Signup, idle customer state ---------------------------------
      testWidgets('signup renders its Arabic idle-state baseline', (
        WidgetTester tester,
      ) async {
        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<AuthBloc>(
            create: (_) => AuthBloc(apiService: _OfflineAuthApiService()),
            child: withMerzoxGoldenDeviceInsets(
              SignupPage(onSignupCreated: () {}, onLoginRequested: () {}),
            ),
          ),
        );

        // The seed is the untouched customer form: no typing, validation,
        // submission, navigation or network request is part of this capture.
        expect(find.text('إنشاء حساب'), findsOneWidget);
        expect(find.text('إنشاء الحساب'), findsWidgets);
        expect(find.text('أنثى'), findsOneWidget);
        expect(find.text('ذكر'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);

        await expectMerzoxSeedGolden('signup_idle_ar_375x812.png');
      });

      // -- 5. Store preview, loaded state ---------------------------------
      testWidgets('store preview renders its Arabic loaded-state baseline', (
        WidgetTester tester,
      ) async {
        _useAuthenticatedMerchantSession();

        final BusinessBloc merchantBloc = BusinessBloc(
          apiService: _SeedMerchantApi(),
        );
        _closeOnTearDown(merchantBloc);

        final Future<BusinessState> merchantReady = merchantBloc.stream
            .firstWhere(
              (BusinessState state) => state.status == BusinessStatus.ready,
            );
        merchantBloc.add(const BusinessStarted());
        await merchantReady;

        final BusinessProfileBloc storefrontBloc = BusinessProfileBloc(
          apiService: _SeedStorefrontApi(),
          viewMode: BusinessProfileViewMode.merchantPreview,
        );

        final Future<BusinessProfileState> storefrontReady = storefrontBloc
            .stream
            .firstWhere(
              (BusinessProfileState state) =>
                  state.status == BusinessProfileStatus.ready,
            );
        storefrontBloc.add(const BusinessProfileStarted(_previewBusinessId));
        await storefrontReady;

        // The seed must be the real LOADED preview, not a spinner, an error or
        // an uninitialised screen. Assert that before capturing, so a silent
        // downgrade fails the test instead of producing a misleading PNG.
        expect(storefrontBloc.state.business, isNotNull);
        expect(
          storefrontBloc.state.detailsStatus,
          BusinessProfileSectionStatus.ready,
        );

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<BusinessBloc>.value(
            value: merchantBloc,
            // `storefrontBloc` is the production test seam; the page's own
            // `BlocProvider` takes ownership and disposes it.
            child: withMerzoxGoldenDeviceInsets(
              StorePreviewPage(storefrontBloc: storefrontBloc),
            ),
          ),
        );

        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('متجر الياسمين'), findsOneWidget);

        await expectMerzoxSeedGolden('store_preview_loaded_ar_375x812.png');
      });

      // -- 6. Cart, guest state -------------------------------------------
      //
      // `السلة` in the XD corpus is the UNAUTHENTICATED cart: the guest mark,
      // the sign-in prompt, the two account actions and the shell's bottom
      // navigation. `HomeScreen` owns that state through `_CartTab`, so the
      // seed renders the real shell on tab 1 rather than a lifted-out widget.
      testWidgets('cart renders its Arabic guest-state baseline', (
        WidgetTester tester,
      ) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});

        final HomeBloc homeBloc = HomeBloc(
          apiService: _OfflineHomeApiService(),
        );
        _closeOnTearDown(homeBloc);

        // Only the tab selection. `HomeStarted` is deliberately never
        // dispatched: it would begin catalog loading and the location
        // permission flow, neither of which is part of this state.
        final Future<HomeState> cartSelected = homeBloc.stream.firstWhere(
          (HomeState state) => state.selectedTab == 1,
        );
        homeBloc.add(const HomeTabChanged(1));
        await cartSelected;

        expect(homeBloc.state.shouldAskLocationPermission, isFalse);

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<HomeBloc>.value(
            value: homeBloc,
            child: withMerzoxGoldenDeviceInsets(
              const HomeScreen(isGuest: true),
            ),
          ),
        );

        // The seed is the guest prompt, not a populated basket: assert the
        // state before capturing so a silent downgrade fails the test rather
        // than producing a misleading PNG.
        expect(find.text('السلة'), findsOneWidget);
        expect(find.text('إنشاء حساب'), findsOneWidget);
        expect(find.text('تسجيل دخول'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);

        await expectMerzoxSeedGolden('cart_guest_ar_375x812.png');
      });

      // -- 7. Order tracking, placed state --------------------------------
      testWidgets('order tracking renders its Arabic placed-state baseline', (
        WidgetTester tester,
      ) async {
        _useAuthenticatedCustomerSession();

        final OrderTrackingBloc trackingBloc = OrderTrackingBloc(
          orderId: _trackedOrderId,
          apiService: _SeedOrderTrackingApi(),
        );
        _closeOnTearDown(trackingBloc);

        final Future<OrderTrackingState> ready = trackingBloc.stream.firstWhere(
          (OrderTrackingState state) =>
              state.status == OrderTrackingStatus.ready,
        );
        trackingBloc.add(const OrderTrackingStarted());
        await ready;

        // The seed must be the real LOADED order, not a spinner or an error.
        expect(trackingBloc.state.order, isNotNull);
        expect(trackingBloc.state.order!.publicId, '222321');

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<OrderTrackingBloc>.value(
            value: trackingBloc,
            child: withMerzoxGoldenDeviceInsets(const OrderTrackingPage()),
          ),
        );

        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('222321'), findsOneWidget);

        await expectMerzoxSeedGolden('order_tracking_placed_ar_375x812.png');
      });

      // -- 8. About Us, loaded state with every section collapsed ---------
      testWidgets('about us renders its Arabic loaded-state baseline', (
        WidgetTester tester,
      ) async {
        final AboutUsBloc aboutBloc = AboutUsBloc(
          apiService: _SeedAboutUsApi(),
        );
        _closeOnTearDown(aboutBloc);

        final Future<AboutUsState> ready = aboutBloc.stream.firstWhere(
          (AboutUsState state) => state.status == AboutUsStatus.ready,
        );
        aboutBloc.add(const AboutUsStarted('ar'));
        await ready;

        expect(aboutBloc.state.content, isNotNull);
        expect(aboutBloc.state.expandedSectionKeys, isEmpty);

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<AboutUsBloc>.value(
            value: aboutBloc,
            child: withMerzoxGoldenDeviceInsets(const AboutUsPage()),
          ),
        );

        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('آلية العمل'), findsOneWidget);
        expect(find.text('شروط العمل'), findsOneWidget);
        expect(find.text('أحكام العمل'), findsOneWidget);

        await expectMerzoxSeedGolden('about_us_loaded_ar_375x812.png');
      });

      // -- 9. Favorites, products tab -------------------------------------
      testWidgets('favorites renders its Arabic products-tab baseline', (
        WidgetTester tester,
      ) async {
        _useAuthenticatedCustomerSession();

        final FavoritesBloc favoritesBloc = FavoritesBloc(
          apiService: _SeedFavoritesApi(),
        );
        _closeOnTearDown(favoritesBloc);

        // The artboard shows the PRODUCTS tab selected; the bloc opens on
        // businesses, so the seed selects it explicitly.
        final Future<FavoritesState> ready = favoritesBloc.stream.firstWhere(
          (FavoritesState state) =>
              state.status == FavoritesStatus.ready &&
              state.selectedTab == FavoritesTab.products &&
              state.productsLoaded,
        );
        favoritesBloc.add(const FavoritesStarted());
        favoritesBloc.add(const FavoritesTabChanged(FavoritesTab.products));
        await ready;

        expect(favoritesBloc.state.products, hasLength(4));

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<FavoritesBloc>.value(
            value: favoritesBloc,
            child: withMerzoxGoldenDeviceInsets(const FavoritesPage()),
          ),
        );

        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('المفضلة'), findsOneWidget);

        await expectMerzoxSeedGolden('favorites_products_ar_375x812.png');
      });
    },
    skip: merzoxGoldenPlatformSkip,
  );
}
