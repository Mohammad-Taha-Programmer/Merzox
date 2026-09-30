import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/features/home/presentation/bloc/home_bloc.dart';
import 'package:merzox/features/home/presentation/bloc/home_event.dart';
import 'package:merzox/features/home/presentation/bloc/home_state_.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/services/device_location_service.dart';
import 'package:merzox/services/location_permission_service.dart';
import 'package:merzox/services/recommendation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_test_fixtures.dart';

/// How long the shops take to appear when the screen opens.
///
/// Three things were making that longer than it had to be, and two of them
/// are here. The screen waited for `المتاجر` - fifty shops for a tab nobody is
/// looking at, and the slowest request on the screen - before drawing the
/// three bands that are. And everything after that ran strictly in turn, so
/// the suggestions band at the top of the screen arrived after a location fix
/// and a favourites request it has nothing to do with.
///
/// The third was on the server: a listed shop was read whole, goods and all.
const int _storesPageSize = 50;

class _GatedApi extends ApiService {
  /// Held open to keep `المتاجر` in the air.
  Completer<void>? storesGate;

  /// Held open to keep the three trailing reads in the air.
  Completer<void>? trailingGate;

  int storesCalls = 0;

  /// Which of the trailing three have been started, in order.
  final List<String> started = <String>[];

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
    if (latitude != null) {
      started.add('nearby');
      await trailingGate?.future;

      return businessPage(
        businesses: <SearchBusinessApiModel>[catalogBusiness(name: 'قريب')],
      );
    }

    if (limit == _storesPageSize) {
      storesCalls += 1;
      await storesGate?.future;

      return businessPage(
        businesses: <SearchBusinessApiModel>[catalogBusiness(name: 'كل')],
      );
    }

    return businessPage(
      businesses: <SearchBusinessApiModel>[catalogBusiness(name: 'بند')],
    );
  }

  @override
  Future<FavoriteBusinessListApiResponse> favoriteBusinesses({
    required String token,
    int page = 1,
    int limit = 20,
  }) async {
    started.add('favourites');
    await trailingGate?.future;

    return const FavoriteBusinessListApiResponse(
      businesses: <SearchBusinessApiModel>[],
      page: 1,
      total: 0,
      hasMore: false,
    );
  }
}

class _Permission extends LocationPermissionService {
  final bool granted;

  _Permission(this.granted);

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

final class _GatedRecommendations implements HomeRecommendationGateway {
  final _GatedApi api;

  _GatedRecommendations(this.api);

  @override
  Future<HomeRecommendationSnapshot> load({required String token}) async {
    api.started.add('suggestions');
    await api.trailingGate?.future;

    return const HomeRecommendationSnapshot(consentEnabled: true);
  }
}

class _SignedIn extends AuthSessionService {
  const _SignedIn();

  @override
  Future<AuthSessionSnapshot> read() async => const AuthSessionSnapshot(
    type: AuthSessionType.customer,
    token: 'first-paint-token',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  HomeBloc open(_GatedApi api, {bool locationGranted = true}) {
    final HomeBloc bloc = HomeBloc(
      apiService: api,
      locationPermissionService: _Permission(locationGranted),
      deviceLocationService: _FixedLocation(),
      authSessionService: const _SignedIn(),
      recommendationGateway: _GatedRecommendations(api),
    );
    addTearDown(() => unawaited(bloc.close()));

    return bloc;
  }

  test('the bands do not wait for the tab nobody is looking at', () async {
    final _GatedApi api = _GatedApi()..storesGate = Completer<void>();
    final HomeBloc bloc = open(api);

    final Future<HomeState> painted = bloc.stream.firstWhere(
      (HomeState state) => state.newBusinessesStatus == HomeSectionStatus.ready,
    );
    bloc.add(const HomeStarted(isGuest: false));
    await painted;

    // The three bands the reader is looking at are on the screen.
    expect(bloc.state.newBusinesses, hasLength(1));
    expect(bloc.state.bestBusinessesStatus, HomeSectionStatus.ready);
    expect(bloc.state.discountedBusinessesStatus, HomeSectionStatus.ready);

    // `المتاجر` is still in the air, and was asked for all the same, so the
    // tab is ready when it is opened.
    expect(api.storesCalls, 1);
    expect(bloc.state.allBusinessesStatus, HomeSectionStatus.loading);

    api.storesGate!.complete();
    await bloc.stream.firstWhere(
      (HomeState state) => state.allBusinessesStatus == HomeSectionStatus.ready,
    );

    expect(bloc.state.allBusinesses, hasLength(1));
  });

  test('the store list still arrives, and says how far it got', () async {
    final _GatedApi api = _GatedApi();
    final HomeBloc bloc = open(api);

    final Future<HomeState> settled = bloc.stream.firstWhere(
      (HomeState state) => state.allBusinessesStatus == HomeSectionStatus.ready,
    );
    bloc.add(const HomeStarted(isGuest: false));
    await settled;

    expect(bloc.state.allBusinesses.single.name, 'كل');
    expect(bloc.state.allBusinessesPage, 1);
  });

  test('the store tab is not held behind unrelated home requests', () async {
    final _GatedApi api = _GatedApi()..trailingGate = Completer<void>();
    final HomeBloc bloc = open(api);

    final Future<HomeState> storesReady = bloc.stream.firstWhere(
      (HomeState state) => state.allBusinessesStatus == HomeSectionStatus.ready,
    );
    bloc.add(const HomeStarted(isGuest: false));
    await storesReady;

    expect(bloc.state.allBusinesses, hasLength(1));
    expect(api.started, contains('suggestions'));
    expect(api.started, contains('favourites'));
    expect(api.trailingGate!.isCompleted, isFalse);

    api.trailingGate!.complete();
    await bloc.stream.firstWhere(
      (HomeState state) => state.recommendationConsentEnabled,
    );
  });

  test('the last three reads run together, not one after another', () async {
    // The suggestions band sits at the top of the screen and used to be
    // fetched last of three, behind a location fix and a favourites request
    // that have nothing to do with it.
    final _GatedApi api = _GatedApi()..trailingGate = Completer<void>();
    final HomeBloc bloc = open(api);

    bloc.add(const HomeStarted(isGuest: false));
    await bloc.stream.firstWhere(
      (HomeState state) => state.newBusinessesStatus == HomeSectionStatus.ready,
    );
    await Future<void>.delayed(Duration.zero);

    // All three in the air at once, while none of them has answered.
    expect(api.started.toSet(), <String>{
      'nearby',
      'favourites',
      'suggestions',
    });

    api.trailingGate!.complete();
  });

  test('a reader who refused location is not waited on for one', () async {
    final _GatedApi api = _GatedApi()..trailingGate = Completer<void>();
    final HomeBloc bloc = open(api, locationGranted: false);

    bloc.add(const HomeStarted(isGuest: false));
    await bloc.stream.firstWhere(
      (HomeState state) => state.newBusinessesStatus == HomeSectionStatus.ready,
    );
    await Future<void>.delayed(Duration.zero);

    expect(api.started, isNot(contains('nearby')));
    expect(bloc.state.nearbyBusinessesStatus, HomeSectionStatus.ready);

    api.trailingGate!.complete();
  });
}
