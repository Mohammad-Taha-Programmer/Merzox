import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/features/home/home_screen.dart';
import 'package:merzox/features/home/presentation/bloc/home_bloc.dart';
import 'package:merzox/features/home/presentation/bloc/home_event.dart';
import 'package:merzox/features/home/presentation/bloc/home_state_.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/services/device_location_service.dart';
import 'package:merzox/services/location_permission_service.dart';
import 'package:merzox/services/recommendation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_test_fixtures.dart';
import 'localization_test_harness.dart';

/// Pull the customer's home screen down, and get the screen again.
///
/// Five bands, each fetched once when the screen opened and then held for as
/// long as the app ran - so a shop that opened, a sale that started or a
/// suggestion that changed stayed invisible until the app was restarted. What
/// a pull must not do is empty the screen it is refreshing.

/// The page size `المتاجر` asks for, which is how this file tells its requests
/// apart from the home bands'.
const int _storesPageSize = 50;

class _CountingApi extends ApiService {
  int newestCalls = 0;
  int bestCalls = 0;
  int offersCalls = 0;
  int storesCalls = 0;
  int nearbyCalls = 0;
  int favoriteCalls = 0;

  /// Set to make every newest request fail.
  bool newestFails = false;

  /// Held open to keep a refresh in flight.
  Completer<void>? gate;

  String newestName = 'متجر الياسمين';

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
    String name = 'متجر';

    if (latitude != null) {
      nearbyCalls += 1;
      name = 'متجر قريب';
    } else if (limit == _storesPageSize) {
      storesCalls += 1;
      name = 'كل المتاجر';
    } else if (discounted == true) {
      offersCalls += 1;
      name = 'عروض';
    } else if (sort == 'rating') {
      bestCalls += 1;
      name = 'الأفضل';
    } else {
      newestCalls += 1;
      name = newestName;
    }

    await gate?.future;

    if (name == newestName && newestFails) {
      throw StateError('the catalogue is offline');
    }

    return businessPage(
      businesses: <SearchBusinessApiModel>[
        catalogBusiness(
          id: '64b00000000000000000000${name.length % 9}',
          name: name,
        ),
      ],
    );
  }

  @override
  Future<FavoriteBusinessListApiResponse> favoriteBusinesses({
    required String token,
    int page = 1,
    int limit = 20,
  }) async {
    favoriteCalls += 1;

    return const FavoriteBusinessListApiResponse(
      businesses: <SearchBusinessApiModel>[],
      page: 1,
      total: 0,
      hasMore: false,
    );
  }
}

class _NoLocation extends LocationPermissionService {
  final bool granted;

  _NoLocation({this.granted = false});

  @override
  Future<bool> isLocationGranted() async => granted;
}

class _FixedLocation extends DeviceLocationService {
  @override
  Future<bool> isServiceEnabled() async => true;

  @override
  Future<DeviceLocation> currentLocation() async =>
      const DeviceLocation(latitude: 31.9, longitude: 35.2);
}

final class _CountingRecommendations implements HomeRecommendationGateway {
  int calls = 0;
  bool consentEnabled = true;
  String name = 'مقترح';

  @override
  Future<HomeRecommendationSnapshot> load({required String token}) async {
    calls += 1;

    if (!consentEnabled) {
      return const HomeRecommendationSnapshot.disabled();
    }

    return HomeRecommendationSnapshot(
      consentEnabled: true,
      personalized: true,
      businesses: <SearchBusinessApiModel>[
        catalogBusiness(id: '64b000000000000000000009', name: name),
      ],
    );
  }
}

class _SignedIn extends AuthSessionService {
  const _SignedIn();

  @override
  Future<AuthSessionSnapshot> read() async => const AuthSessionSnapshot(
    type: AuthSessionType.customer,
    token: 'home-refresh-token',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<HomeBloc> openHome(
    _CountingApi api, {
    _CountingRecommendations? recommendations,
    bool locationGranted = false,
  }) async {
    final HomeBloc bloc = HomeBloc(
      apiService: api,
      locationPermissionService: _NoLocation(granted: locationGranted),
      deviceLocationService: _FixedLocation(),
      authSessionService: const _SignedIn(),
      recommendationGateway: recommendations ?? _CountingRecommendations(),
    );
    addTearDown(() => unawaited(bloc.close()));

    final Future<HomeState> ready = bloc.stream.firstWhere(
      (HomeState state) =>
          state.newBusinessesStatus != HomeSectionStatus.loading &&
          state.newBusinessesStatus != HomeSectionStatus.initial,
    );
    bloc.add(const HomeStarted(isGuest: false));
    await ready;
    // The bands that follow the first emit - nearby, favourites, suggestions.
    await Future<void>.delayed(Duration.zero);

    return bloc;
  }

  test('one pull fetches every band the screen shows', () async {
    final _CountingApi api = _CountingApi();
    final _CountingRecommendations recommendations = _CountingRecommendations();
    final HomeBloc bloc = await openHome(
      api,
      recommendations: recommendations,
      locationGranted: true,
    );

    expect(api.newestCalls, 1);
    expect(api.bestCalls, 1);
    expect(api.offersCalls, 1);
    expect(api.nearbyCalls, 1);
    expect(api.favoriteCalls, 1);
    expect(recommendations.calls, 1);

    await refreshHome(bloc);

    expect(api.newestCalls, 2);
    expect(api.bestCalls, 2);
    expect(api.offersCalls, 2);
    expect(api.nearbyCalls, 2, reason: 'the shops near the reader are a band');
    expect(api.favoriteCalls, 2, reason: 'the hearts are part of the screen');
    expect(recommendations.calls, 2);
    expect(bloc.state.isRefreshing, isFalse);
  });

  test('it leaves the paged store list alone', () async {
    // `المتاجر` is behind its own tab, with its own search field and its own
    // scroll position. Refetching page one of it would throw away however far
    // a reader had got in a list this gesture never touched.
    final _CountingApi api = _CountingApi();
    final HomeBloc bloc = await openHome(api);

    expect(api.storesCalls, 1);

    await refreshHome(bloc);

    expect(api.storesCalls, 1);
  });

  test('the screen it is refreshing is not emptied first', () async {
    final _CountingApi api = _CountingApi();
    final HomeBloc bloc = await openHome(api, locationGranted: true);

    expect(bloc.state.newBusinesses, hasLength(1));
    expect(bloc.state.recommendedBusinesses, hasLength(1));

    api.gate = Completer<void>();
    final Future<void> refresh = refreshHome(bloc);
    await Future<void>.delayed(Duration.zero);

    expect(bloc.state.isRefreshing, isTrue);
    // Every band still standing, and none of them in a loading state.
    expect(bloc.state.newBusinesses, hasLength(1));
    expect(bloc.state.bestBusinesses, hasLength(1));
    expect(bloc.state.nearbyBusinesses, hasLength(1));
    expect(bloc.state.recommendedBusinesses, hasLength(1));
    expect(bloc.state.newBusinessesStatus, HomeSectionStatus.ready);
    expect(bloc.state.nearbyBusinessesStatus, HomeSectionStatus.ready);

    api.gate!.complete();
    await refresh;
  });

  test('a band that fails keeps what it had, and says it failed', () async {
    final _CountingApi api = _CountingApi();
    final HomeBloc bloc = await openHome(api);

    api.newestFails = true;
    await refreshHome(bloc);

    expect(bloc.state.newBusinesses, hasLength(1));
    expect(bloc.state.newBusinessesStatus, HomeSectionStatus.failure);
    expect(bloc.state.newBusinessesError, isNotEmpty);
    // And the bands that answered are the ones that answered.
    expect(bloc.state.bestBusinessesStatus, HomeSectionStatus.ready);
  });

  test('it brings back what changed', () async {
    final _CountingApi api = _CountingApi();
    final _CountingRecommendations recommendations = _CountingRecommendations();
    final HomeBloc bloc = await openHome(api, recommendations: recommendations);

    api.newestName = 'متجر البتول';
    recommendations.name = 'مقترح جديد';
    await refreshHome(bloc);

    expect(bloc.state.newBusinesses.single.name, 'متجر البتول');
    expect(bloc.state.recommendedBusinesses.single.name, 'مقترح جديد');
  });

  test('consent withdrawn between two pulls clears the band', () async {
    // The band is no longer emptied before the request, so the answer has to
    // be the thing that empties it.
    final _CountingApi api = _CountingApi();
    final _CountingRecommendations recommendations = _CountingRecommendations();
    final HomeBloc bloc = await openHome(api, recommendations: recommendations);

    expect(bloc.state.recommendedBusinesses, hasLength(1));

    recommendations.consentEnabled = false;
    await refreshHome(bloc);

    expect(bloc.state.recommendedBusinesses, isEmpty);
    expect(bloc.state.recommendationConsentEnabled, isFalse);
  });

  test('a second pull joins the one already running', () async {
    final _CountingApi api = _CountingApi();
    final HomeBloc bloc = await openHome(api);

    api.gate = Completer<void>();
    final Future<void> first = refreshHome(bloc);
    await Future<void>.delayed(Duration.zero);
    final Future<void> second = refreshHome(bloc);

    api.gate!.complete();
    await Future.wait(<Future<void>>[first, second]);

    // One set of requests, not two.
    expect(api.newestCalls, 2);
    expect(api.bestCalls, 2);
  });

  testWidgets('and the gesture is wired to it', (WidgetTester tester) async {
    final _CountingApi api = _CountingApi();
    // Opened outside the fake clock: `openHome` waits on a real timer, which
    // inside `testWidgets` only advances when the test pumps.
    final HomeBloc bloc = (await tester.runAsync(() => openHome(api)))!;

    await pumpLocalized(
      tester,
      BlocProvider<HomeBloc>.value(
        value: bloc,
        child: const HomeScreen(isGuest: false),
      ),
    );
    await tester.pump();

    expect(api.newestCalls, 1);
    expect(find.byType(RefreshIndicator), findsOneWidget);

    // From near the top of the screen: the gesture has to begin over the
    // scroll view while it is at its start, which is the only place a
    // pull-to-refresh means anything.
    await tester.dragFrom(const Offset(500, 300), const Offset(0, 700));
    await settleFrames(tester);

    expect(api.newestCalls, 2);
  });
}
