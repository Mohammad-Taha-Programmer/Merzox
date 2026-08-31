import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/home/presentation/bloc/home_bloc.dart';
import 'package:merzox/features/home/presentation/bloc/home_event.dart';
import 'package:merzox/features/home/presentation/bloc/home_state_.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/services/device_location_service.dart';
import 'package:merzox/services/location_permission_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_test_fixtures.dart';

final class _BusinessRequest {
  final int page;
  final int limit;
  final String? search;
  final String? sort;
  final bool? discounted;
  final double? latitude;
  final double? longitude;
  final int? radiusMeters;

  const _BusinessRequest({
    required this.page,
    required this.limit,
    this.search,
    this.sort,
    this.discounted,
    this.latitude,
    this.longitude,
    this.radiusMeters,
  });
}

/// The page size `المتاجر` asks for, which is how these tests tell its
/// requests apart from the home sections'.
const int _storesPageSize = 50;

class _FakeCatalogApi extends ApiService {
  final Future<BusinessListApiResponse> Function(_BusinessRequest request)
  handler;
  final List<_BusinessRequest> requests = [];

  _FakeCatalogApi(this.handler);

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
  }) {
    final request = _BusinessRequest(
      page: page,
      limit: limit,
      search: search,
      sort: sort,
      discounted: discounted,
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
    );
    requests.add(request);
    return handler(request);
  }
}

class _FakeLocationPermissionService extends LocationPermissionService {
  final bool granted;

  _FakeLocationPermissionService(this.granted);

  @override
  Future<bool> isLocationGranted() async => granted;
}

class _FakeDeviceLocationService extends DeviceLocationService {
  int currentLocationCalls = 0;

  @override
  Future<bool> isServiceEnabled() async => true;

  @override
  Future<DeviceLocation> currentLocation() async {
    currentLocationCalls += 1;
    return const DeviceLocation(latitude: 31.9, longitude: 35.2);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'Home loads new, best, offers, and all businesses from API data',
    () async {
      final newest = catalogBusiness(name: 'Newest');
      final best = catalogBusiness(
        id: '64b000000000000000000002',
        name: 'Best',
        rating: 4.9,
      );
      final offer = catalogBusiness(
        id: '64b000000000000000000003',
        name: 'Offer',
        discount: '15%',
      );
      final api = _FakeCatalogApi((request) async {
        if (request.limit == _storesPageSize) {
          return businessPage(
            businesses: [newest, best],
            limit: _storesPageSize,
          );
        }
        if (request.discounted == true) {
          return businessPage(businesses: [offer]);
        }
        if (request.sort == 'rating') {
          return businessPage(businesses: [best]);
        }
        return businessPage(businesses: [newest]);
      });
      final bloc = _homeBloc(api: api, permissionGranted: false);
      addTearDown(bloc.close);

      final state = await _startHome(bloc);

      expect(state.newBusinesses.single.name, 'Newest');
      expect(state.bestBusinesses.single.name, 'Best');
      expect(state.discountedBusinesses.single.discount, '15%');
      expect(state.allBusinesses.map((item) => item.name), ['Newest', 'Best']);
      expect(api.requests.any((request) => request.sort == 'rating'), isTrue);
      expect(api.requests.any((request) => request.discounted == true), isTrue);
    },
  );

  test('Home keeps a successful empty API catalog empty', () async {
    final api = _FakeCatalogApi((_) async => businessPage());
    final bloc = _homeBloc(api: api, permissionGranted: false);
    addTearDown(bloc.close);

    final state = await _startHome(bloc);

    expect(state.newBusinesses, isEmpty);
    expect(state.bestBusinesses, isEmpty);
    expect(state.discountedBusinesses, isEmpty);
    expect(state.allBusinesses, isEmpty);
    expect(state.newBusinessesStatus, HomeSectionStatus.ready);
    expect(state.allBusinessesStatus, HomeSectionStatus.ready);
  });

  test('Home exposes API failures without injecting businesses', () async {
    final api = _FakeCatalogApi((_) async => throw StateError('offline'));
    final bloc = _homeBloc(api: api, permissionGranted: false);
    addTearDown(bloc.close);

    final state = await _startHome(bloc);

    expect(state.newBusinesses, isEmpty);
    expect(state.bestBusinesses, isEmpty);
    expect(state.discountedBusinesses, isEmpty);
    expect(state.allBusinesses, isEmpty);
    expect(state.newBusinessesStatus, HomeSectionStatus.failure);
    expect(state.bestBusinessesStatus, HomeSectionStatus.failure);
    expect(state.discountedBusinessesStatus, HomeSectionStatus.failure);
    expect(state.allBusinessesStatus, HomeSectionStatus.failure);
  });

  test(
    'All-business pagination requests page 2 and de-duplicates results',
    () async {
      final first = catalogBusiness(name: 'First');
      final duplicate = catalogBusiness(
        id: '64b000000000000000000002',
        name: 'Second',
      );
      final third = catalogBusiness(
        id: '64b000000000000000000003',
        name: 'Third',
      );
      final api = _FakeCatalogApi((request) async {
        if (request.limit != _storesPageSize) return businessPage();
        if (request.page == 1) {
          return businessPage(
            businesses: [first, duplicate],
            page: 1,
            limit: _storesPageSize,
            hasMore: true,
            total: 3,
          );
        }
        return businessPage(
          businesses: [duplicate, third],
          page: 2,
          limit: _storesPageSize,
          hasMore: false,
          total: 3,
        );
      });
      final bloc = _homeBloc(api: api, permissionGranted: false);
      addTearDown(bloc.close);

      final firstPage = await _startHome(bloc);
      expect(firstPage.allBusinessesPage, 1);
      expect(firstPage.hasMoreAllBusinesses, isTrue);

      final secondPageFuture = bloc.stream.firstWhere(
        (state) => state.allBusinessesPage == 2,
      );
      bloc.add(const HomeAllBusinessesNextPageRequested());
      final secondPage = await secondPageFuture;

      expect(secondPage.allBusinesses.map((item) => item.name), [
        'First',
        'Second',
        'Third',
      ]);
      expect(secondPage.hasMoreAllBusinesses, isFalse);
      expect(
        api.requests
            .where((request) => request.limit == _storesPageSize)
            .map((request) => request.page),
        [1, 2],
      );
    },
  );

  // `المتاجر` searches the server, not the page it is holding. The tab is
  // paged, so a filter applied in the widget could only ever find shops that
  // had already been fetched - a shop on page three would not exist.

  test('a stores search reaches the server and replaces the list', () async {
    final all = catalogBusiness(name: 'Everything');
    final match = catalogBusiness(
      id: '64b000000000000000000009',
      name: 'Yasmeen',
    );

    final api = _FakeCatalogApi((request) async {
      if (request.limit != _storesPageSize) return businessPage();

      return (request.search ?? '').isEmpty
          ? businessPage(businesses: [all], limit: _storesPageSize)
          : businessPage(businesses: [match], limit: _storesPageSize);
    });

    final bloc = _homeBloc(api: api, permissionGranted: false);
    addTearDown(bloc.close);

    final loaded = await _startHome(bloc);
    expect(loaded.allBusinesses.single.name, 'Everything');

    final searched = bloc.stream.firstWhere(
      (HomeState state) =>
          state.allBusinessesSearch == 'Yasmeen' &&
          state.allBusinessesStatus == HomeSectionStatus.ready,
    );
    bloc.add(const HomeAllBusinessesSearchChanged('  Yasmeen  '));

    final state = await searched;

    // Trimmed, sent, and the previous page dropped rather than merged.
    expect(state.allBusinessesSearch, 'Yasmeen');
    expect(state.allBusinesses.map((item) => item.name), ['Yasmeen']);
    expect(
      api.requests
          .where((request) => request.limit == _storesPageSize)
          .map((request) => request.search),
      ['', 'Yasmeen'],
    );
  });

  test('the second page of a search stays inside that search', () async {
    final first = catalogBusiness(name: 'Match one');
    final second = catalogBusiness(
      id: '64b000000000000000000008',
      name: 'Match two',
    );

    final api = _FakeCatalogApi((request) async {
      if (request.limit != _storesPageSize) return businessPage();

      return businessPage(
        businesses: <SearchBusinessApiModel>[
          request.page == 1 ? first : second,
        ],
        page: request.page,
        limit: _storesPageSize,
        hasMore: request.page == 1,
        total: 2,
      );
    });

    final bloc = _homeBloc(api: api, permissionGranted: false);
    addTearDown(bloc.close);

    await _startHome(bloc);

    final searched = bloc.stream.firstWhere(
      (HomeState state) =>
          state.allBusinessesSearch == 'Match' &&
          state.allBusinessesStatus == HomeSectionStatus.ready,
    );
    bloc.add(const HomeAllBusinessesSearchChanged('Match'));
    await searched;

    final paged = bloc.stream.firstWhere(
      (HomeState state) => state.allBusinessesPage == 2,
    );
    bloc.add(const HomeAllBusinessesNextPageRequested());
    await paged;

    // Without the term, page two would arrive unfiltered and be merged into a
    // filtered list.
    expect(
      api.requests
          .where(
            (request) => request.limit == _storesPageSize && request.page == 2,
          )
          .map((request) => request.search),
      ['Match'],
    );
    expect(bloc.state.allBusinesses, hasLength(2));
  });

  test('re-typing the same query does not ask again', () async {
    final api = _FakeCatalogApi(
      (request) async => businessPage(limit: request.limit),
    );

    final bloc = _homeBloc(api: api, permissionGranted: false);
    addTearDown(bloc.close);

    await _startHome(bloc);

    final searched = bloc.stream.firstWhere(
      (HomeState state) => state.allBusinessesSearch == 'Yasmeen',
    );
    bloc.add(const HomeAllBusinessesSearchChanged('Yasmeen'));
    await searched;

    final int before = api.requests.length;
    bloc.add(const HomeAllBusinessesSearchChanged('Yasmeen'));
    await Future<void>.delayed(Duration.zero);

    expect(api.requests.length, before);
  });

  test(
    'Nearby uses granted device coordinates and backend distance data',
    () async {
      final nearby = catalogBusiness(name: 'Nearby', distanceMeters: 420);
      final api = _FakeCatalogApi((request) async {
        if (request.latitude != null) {
          return businessPage(businesses: [nearby]);
        }
        return businessPage();
      });
      final device = _FakeDeviceLocationService();
      final bloc = HomeBloc(
        apiService: api,
        deviceLocationService: device,
        locationPermissionService: _FakeLocationPermissionService(true),
      );
      addTearDown(bloc.close);

      final state = await _startHome(bloc);

      expect(state.nearbyBusinesses.single.name, 'Nearby');
      expect(state.nearbyBusinesses.single.distanceMeters, 420);
      expect(device.currentLocationCalls, 1);
      final request = api.requests.singleWhere(
        (request) => request.latitude != null,
      );
      expect(request.latitude, 31.9);
      expect(request.longitude, 35.2);
      expect(request.radiusMeters, 25000);
    },
  );

  test('Nearby stays empty when location permission is unavailable', () async {
    final api = _FakeCatalogApi((_) async => businessPage());
    final device = _FakeDeviceLocationService();
    final bloc = HomeBloc(
      apiService: api,
      deviceLocationService: device,
      locationPermissionService: _FakeLocationPermissionService(false),
    );
    addTearDown(bloc.close);

    final state = await _startHome(bloc);

    expect(state.nearbyBusinesses, isEmpty);
    expect(state.nearbyBusinessesStatus, HomeSectionStatus.ready);
    expect(device.currentLocationCalls, 0);
    expect(api.requests.where((request) => request.latitude != null), isEmpty);
  });
}

HomeBloc _homeBloc({required ApiService api, required bool permissionGranted}) {
  return HomeBloc(
    apiService: api,
    deviceLocationService: _FakeDeviceLocationService(),
    locationPermissionService: _FakeLocationPermissionService(
      permissionGranted,
    ),
  );
}

Future<HomeState> _startHome(HomeBloc bloc) {
  final stateFuture = bloc.stream.firstWhere((state) {
    return state.newBusinessesStatus != HomeSectionStatus.initial &&
        state.newBusinessesStatus != HomeSectionStatus.loading &&
        state.bestBusinessesStatus != HomeSectionStatus.initial &&
        state.bestBusinessesStatus != HomeSectionStatus.loading &&
        state.discountedBusinessesStatus != HomeSectionStatus.initial &&
        state.discountedBusinessesStatus != HomeSectionStatus.loading &&
        state.allBusinessesStatus != HomeSectionStatus.initial &&
        state.allBusinessesStatus != HomeSectionStatus.loading &&
        state.nearbyBusinessesStatus != HomeSectionStatus.initial &&
        state.nearbyBusinessesStatus != HomeSectionStatus.loading;
  });
  bloc.add(const HomeStarted(isGuest: true));
  return stateFuture;
}
