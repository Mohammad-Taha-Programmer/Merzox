// MERZOX-UI-GOLDEN-I4-I1 - the four deterministic seed goldens.
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
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/authentication/pages/login_page.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/features/business/preview/store_preview_page.dart';
import 'package:merzox/features/business/shell/business_bloc.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_bloc.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_event.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_state.dart';
import 'package:merzox/features/business_profile/business_profile_view_mode.dart';
import 'package:merzox/features/onboarding/bloc/onboarding_bloc.dart';
import 'package:merzox/features/onboarding/view/onboarding_screen.dart';
import 'package:merzox/features/splash/presentation/splash_screen.dart';
import 'package:merzox/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'merzox_golden_harness.dart';

// ---------------------------------------------------------------------------
// Login fixture
// ---------------------------------------------------------------------------

/// An [ApiService] that cannot reach the network.
///
/// The idle login golden never submits the form, so any call here means the
/// capture drifted into a request-driven state and the test should say so
/// rather than quietly hit a real endpoint.
final class _OfflineAuthApiService extends ApiService {
  @override
  Future<AuthApiResponse> login({
    required String identifier,
    required String password,
  }) async {
    throw StateError('the idle login golden must not call login()');
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
    throw StateError('the idle login golden must not call signup()');
  }
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
            child: OnboardingScreen(onFinished: () {}),
          ),
        );

        // The seed is the first page only: no swipe, no skip, no completion.
        // These are the same Arabic labels the existing onboarding widget test
        // asserts for the initial state.
        expect(find.text('أفضل العروض القريبة منك'), findsOneWidget);
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
            child: LoginPage(
              onAuthenticated: () {},
              onBrowseAsGuest: () {},
              onSignupRequested: () {},
              onForgotPasswordRequested: () {},
              businessMode: false,
            ),
          ),
        );

        await expectMerzoxSeedGolden('login_idle_ar_375x812.png');
      });

      // -- 4. Store preview, loaded state ---------------------------------
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
            child: StorePreviewPage(storefrontBloc: storefrontBloc),
          ),
        );

        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('متجر الياسمين'), findsOneWidget);

        await expectMerzoxSeedGolden('store_preview_loaded_ar_375x812.png');
      });
    },
    skip: merzoxGoldenPlatformSkip,
  );
}
