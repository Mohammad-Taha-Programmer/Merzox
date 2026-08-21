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
        if (request.limit == 100) {
          return businessPage(businesses: [newest, best], limit: 100);
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
        if (request.limit != 100) return businessPage();
        if (request.page == 1) {
          return businessPage(
            businesses: [first, duplicate],
            page: 1,
            limit: 100,
            hasMore: true,
            total: 3,
          );
        }
        return businessPage(
          businesses: [duplicate, third],
          page: 2,
          limit: 100,
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
            .where((request) => request.limit == 100)
            .map((request) => request.page),
        [1, 2],
      );
    },
  );

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
