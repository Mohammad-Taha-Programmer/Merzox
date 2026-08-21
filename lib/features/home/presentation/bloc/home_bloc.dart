import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/services/device_location_service.dart';
import 'package:merzox/services/location_permission_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_event.dart';
import 'home_state_.dart';

class HomeBloc extends Bloc<HomeEvent, HomeState> {
  final ApiService _apiService;
  final DeviceLocationService _deviceLocationService;
  final LocationPermissionService _locationPermissionService;
  final AuthSessionService _authSessionService;

  HomeBloc({
    ApiService? apiService,
    DeviceLocationService? deviceLocationService,
    LocationPermissionService? locationPermissionService,
    AuthSessionService authSessionService = const AuthSessionService(),
  }) : _apiService = apiService ?? ApiService(),
       _deviceLocationService =
           deviceLocationService ?? DeviceLocationService(),
       _locationPermissionService =
           locationPermissionService ?? LocationPermissionService(),
       _authSessionService = authSessionService,
       super(const HomeState()) {
    on<HomeStarted>(_onStarted);
    on<HomeSearchChanged>(_onSearchChanged);
    on<HomeTabChanged>(_onTabChanged);
    on<HomeLocationPromptShown>(_onLocationPromptShown);
    on<HomeLocationServiceRequested>(_onLocationServiceRequested);
    on<HomeLocationPermissionAnswered>(_onLocationPermissionAnswered);
    on<HomeBusinessFollowToggled>(_onBusinessFollowToggled);
    on<HomeAllBusinessesNextPageRequested>(_onAllBusinessesNextPageRequested);
    on<HomeCatalogSectionRetryRequested>(_onCatalogSectionRetryRequested);
  }

  Future<void> _onStarted(HomeStarted event, Emitter<HomeState> emit) async {
    final prefs = await SharedPreferences.getInstance();
    final session = await _authSessionService.read();
    final permissionGranted = await _isLocationPermissionGranted();
    final promptPending =
        prefs.getBool(AuthBloc.locationPromptPendingKey) ?? false;
    final shouldAskAfterLogin =
        session.isAuthenticated && promptPending && !permissionGranted;

    emit(
      state.copyWith(
        selectedTab: event.initialTab.clamp(0, 4),
        shouldAskLocationPermission: shouldAskAfterLogin,
        locationPermissionHandled: !shouldAskAfterLogin,
        locationPermissionGranted: permissionGranted,
        locationPermissionReason: 'firstLogin',
        newBusinesses: const [],
        bestBusinesses: const [],
        discountedBusinesses: const [],
        nearbyBusinesses: const [],
        allBusinesses: const [],
        newBusinessesStatus: HomeSectionStatus.loading,
        bestBusinessesStatus: HomeSectionStatus.loading,
        discountedBusinessesStatus: HomeSectionStatus.loading,
        nearbyBusinessesStatus: permissionGranted
            ? HomeSectionStatus.loading
            : HomeSectionStatus.ready,
        allBusinessesStatus: HomeSectionStatus.loading,
        newBusinessesError: '',
        bestBusinessesError: '',
        discountedBusinessesError: '',
        nearbyBusinessesError: '',
        allBusinessesError: '',
        allBusinessesPage: 0,
        isLoadingAllBusinesses: false,
        hasMoreAllBusinesses: false,
      ),
    );

    final results = await Future.wait([
      _captureBusinesses(
        () => _apiService.businesses(
          page: 1,
          limit: _homeSectionLimit,
          sort: 'newest',
        ),
      ),
      _captureBusinesses(
        () => _apiService.businesses(
          page: 1,
          limit: _homeSectionLimit,
          sort: 'rating',
        ),
      ),
      _captureBusinesses(
        () => _apiService.businesses(
          page: 1,
          limit: _homeSectionLimit,
          sort: 'newest',
          discounted: true,
        ),
      ),
      _captureBusinesses(
        () => _apiService.businesses(
          page: 1,
          limit: _allBusinessesPageSize,
          sort: 'newest',
        ),
      ),
    ]);

    final newest = results[0];
    final best = results[1];
    final offers = results[2];
    final all = results[3];

    emit(
      state.copyWith(
        newBusinesses: _mappedBusinesses(newest.response),
        bestBusinesses: _mappedBusinesses(best.response),
        discountedBusinesses: _mappedBusinesses(offers.response),
        allBusinesses: _mappedBusinesses(all.response),
        newBusinessesStatus: newest.status,
        bestBusinessesStatus: best.status,
        discountedBusinessesStatus: offers.status,
        allBusinessesStatus: all.status,
        newBusinessesError: newest.errorMessage,
        bestBusinessesError: best.errorMessage,
        discountedBusinessesError: offers.errorMessage,
        allBusinessesError: all.errorMessage,
        allBusinessesPage: all.response?.page ?? 0,
        hasMoreAllBusinesses: all.response?.hasMore ?? false,
      ),
    );

    if (permissionGranted) {
      await _loadNearby(emit);
    }

    await _loadFavoriteBusinesses(emit, session);
  }

  void _onSearchChanged(HomeSearchChanged event, Emitter<HomeState> emit) {
    emit(state.copyWith(searchQuery: event.query));
  }

  void _onTabChanged(HomeTabChanged event, Emitter<HomeState> emit) {
    emit(state.copyWith(selectedTab: event.index.clamp(0, 4)));
  }

  void _onLocationPromptShown(
    HomeLocationPromptShown event,
    Emitter<HomeState> emit,
  ) {
    emit(state.copyWith(shouldAskLocationPermission: false));
  }

  Future<void> _onLocationServiceRequested(
    HomeLocationServiceRequested event,
    Emitter<HomeState> emit,
  ) async {
    final granted = await _isLocationPermissionGranted();
    if (granted) {
      emit(state.copyWith(locationPermissionGranted: true));
      await _loadNearby(emit);
      return;
    }

    emit(
      state.copyWith(
        locationPermissionGranted: false,
        nearbyBusinesses: const [],
        nearbyBusinessesStatus: HomeSectionStatus.ready,
        nearbyBusinessesError: '',
        shouldAskLocationPermission: true,
        locationPermissionReason: event.reason,
      ),
    );
  }

  Future<void> _onLocationPermissionAnswered(
    HomeLocationPermissionAnswered event,
    Emitter<HomeState> emit,
  ) async {
    await _persistLocationPermission(granted: event.granted);

    emit(
      state.copyWith(
        locationPermissionHandled: true,
        locationPermissionGranted: event.granted,
        locationPermissionPermanentlyDenied: false,
        shouldAskLocationPermission: false,
        nearbyBusinesses: event.granted ? null : const [],
        nearbyBusinessesStatus: event.granted
            ? HomeSectionStatus.loading
            : HomeSectionStatus.ready,
        nearbyBusinessesError: '',
      ),
    );

    if (event.granted) {
      await _loadNearby(emit);
    }
  }

  Future<void> _persistLocationPermission({required bool granted}) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(AuthBloc.userIdKey);

    await prefs.setBool(AuthBloc.locationPermissionGrantedKey, granted);
    await prefs.setBool(AuthBloc.locationPromptPendingKey, false);

    if (userId != null && userId.isNotEmpty) {
      await prefs.setBool('${AuthBloc.locationPromptAskedPrefix}$userId', true);
    }

    final session = await _authSessionService.read();
    final token = session.token;
    if (token == null) return;

    try {
      await _apiService.updatePermissions(token: token, location: granted);
    } catch (_) {
      // The operating-system permission remains authoritative while offline.
    }
  }

  Future<void> _onBusinessFollowToggled(
    HomeBusinessFollowToggled event,
    Emitter<HomeState> emit,
  ) async {
    final session = await _authSessionService.read();
    final token = session.token;
    if (token == null) return;

    final followedIds = Set<String>.from(state.followedBusinessIds);
    final wasFollowed = followedIds.contains(event.businessId);

    if (wasFollowed) {
      followedIds.remove(event.businessId);
    } else {
      followedIds.add(event.businessId);
    }

    emit(state.copyWith(followedBusinessIds: followedIds));

    try {
      await _apiService.setBusinessFavorited(
        token: token,
        businessId: event.businessId,
        favorited: !wasFollowed,
      );
    } catch (_) {
      final reverted = Set<String>.from(state.followedBusinessIds);
      if (wasFollowed) {
        reverted.add(event.businessId);
      } else {
        reverted.remove(event.businessId);
      }
      emit(state.copyWith(followedBusinessIds: reverted));
    }
  }

  Future<void> _onAllBusinessesNextPageRequested(
    HomeAllBusinessesNextPageRequested event,
    Emitter<HomeState> emit,
  ) async {
    if (state.isLoadingAllBusinesses || !state.hasMoreAllBusinesses) {
      return;
    }

    emit(state.copyWith(isLoadingAllBusinesses: true, allBusinessesError: ''));

    final nextPage = state.allBusinessesPage + 1;
    try {
      final response = await _apiService.businesses(
        page: nextPage,
        limit: _allBusinessesPageSize,
        sort: 'newest',
      );
      final byId = <String, HomeBusiness>{
        for (final business in state.allBusinesses) business.id: business,
      };
      for (final business in _mappedBusinesses(response)) {
        byId.putIfAbsent(business.id, () => business);
      }

      emit(
        state.copyWith(
          allBusinesses: byId.values.toList(),
          allBusinessesPage: response.page,
          isLoadingAllBusinesses: false,
          hasMoreAllBusinesses: response.hasMore,
          allBusinessesStatus: HomeSectionStatus.ready,
          allBusinessesError: '',
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          isLoadingAllBusinesses: false,
          allBusinessesStatus: HomeSectionStatus.failure,
          allBusinessesError: ApiService.messageFromError(error),
        ),
      );
    }
  }

  Future<void> _onCatalogSectionRetryRequested(
    HomeCatalogSectionRetryRequested event,
    Emitter<HomeState> emit,
  ) async {
    switch (event.section) {
      case HomeCatalogSection.newest:
        await _reloadNewest(emit);
      case HomeCatalogSection.best:
        await _reloadBest(emit);
      case HomeCatalogSection.offers:
        await _reloadOffers(emit);
      case HomeCatalogSection.nearby:
        await _loadNearby(emit);
      case HomeCatalogSection.all:
        if (state.allBusinesses.isNotEmpty && state.hasMoreAllBusinesses) {
          await _onAllBusinessesNextPageRequested(
            const HomeAllBusinessesNextPageRequested(),
            emit,
          );
        } else {
          await _reloadAllBusinesses(emit);
        }
    }
  }

  Future<void> _reloadNewest(Emitter<HomeState> emit) async {
    emit(
      state.copyWith(
        newBusinessesStatus: HomeSectionStatus.loading,
        newBusinessesError: '',
      ),
    );
    final result = await _captureBusinesses(
      () => _apiService.businesses(
        page: 1,
        limit: _homeSectionLimit,
        sort: 'newest',
      ),
    );
    emit(
      state.copyWith(
        newBusinesses: _mappedBusinesses(result.response),
        newBusinessesStatus: result.status,
        newBusinessesError: result.errorMessage,
      ),
    );
  }

  Future<void> _reloadBest(Emitter<HomeState> emit) async {
    emit(
      state.copyWith(
        bestBusinessesStatus: HomeSectionStatus.loading,
        bestBusinessesError: '',
      ),
    );
    final result = await _captureBusinesses(
      () => _apiService.businesses(
        page: 1,
        limit: _homeSectionLimit,
        sort: 'rating',
      ),
    );
    emit(
      state.copyWith(
        bestBusinesses: _mappedBusinesses(result.response),
        bestBusinessesStatus: result.status,
        bestBusinessesError: result.errorMessage,
      ),
    );
  }

  Future<void> _reloadOffers(Emitter<HomeState> emit) async {
    emit(
      state.copyWith(
        discountedBusinessesStatus: HomeSectionStatus.loading,
        discountedBusinessesError: '',
      ),
    );
    final result = await _captureBusinesses(
      () => _apiService.businesses(
        page: 1,
        limit: _homeSectionLimit,
        sort: 'newest',
        discounted: true,
      ),
    );
    emit(
      state.copyWith(
        discountedBusinesses: _mappedBusinesses(result.response),
        discountedBusinessesStatus: result.status,
        discountedBusinessesError: result.errorMessage,
      ),
    );
  }

  Future<void> _reloadAllBusinesses(Emitter<HomeState> emit) async {
    emit(
      state.copyWith(
        allBusinesses: const [],
        allBusinessesStatus: HomeSectionStatus.loading,
        allBusinessesError: '',
        allBusinessesPage: 0,
        hasMoreAllBusinesses: false,
      ),
    );
    final result = await _captureBusinesses(
      () => _apiService.businesses(
        page: 1,
        limit: _allBusinessesPageSize,
        sort: 'newest',
      ),
    );
    emit(
      state.copyWith(
        allBusinesses: _mappedBusinesses(result.response),
        allBusinessesStatus: result.status,
        allBusinessesError: result.errorMessage,
        allBusinessesPage: result.response?.page ?? 0,
        hasMoreAllBusinesses: result.response?.hasMore ?? false,
      ),
    );
  }

  Future<void> _loadNearby(Emitter<HomeState> emit) async {
    if (!await _isLocationPermissionGranted()) {
      emit(
        state.copyWith(
          locationPermissionGranted: false,
          nearbyBusinesses: const [],
          nearbyBusinessesStatus: HomeSectionStatus.ready,
          nearbyBusinessesError: '',
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        locationPermissionGranted: true,
        nearbyBusinessesStatus: HomeSectionStatus.loading,
        nearbyBusinessesError: '',
      ),
    );

    try {
      if (!await _deviceLocationService.isServiceEnabled()) {
        emit(
          state.copyWith(
            nearbyBusinesses: const [],
            nearbyBusinessesStatus: HomeSectionStatus.failure,
            nearbyBusinessesError: 'catalog.locationUnavailable',
          ),
        );
        return;
      }

      final location = await _deviceLocationService.currentLocation();
      final response = await _apiService.businesses(
        page: 1,
        limit: _homeSectionLimit,
        latitude: location.latitude,
        longitude: location.longitude,
        radiusMeters: _nearbyRadiusMeters,
      );
      emit(
        state.copyWith(
          nearbyBusinesses: _mappedBusinesses(response),
          nearbyBusinessesStatus: HomeSectionStatus.ready,
          nearbyBusinessesError: '',
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          nearbyBusinesses: const [],
          nearbyBusinessesStatus: HomeSectionStatus.failure,
          nearbyBusinessesError: ApiService.messageFromError(error),
        ),
      );
    }
  }

  Future<void> _loadFavoriteBusinesses(
    Emitter<HomeState> emit,
    AuthSessionSnapshot session,
  ) async {
    final token = session.token;
    if (token == null) return;

    try {
      final response = await _apiService.favoriteBusinesses(
        token: token,
        limit: 100,
      );
      final followedIds = <String>{};
      for (final business in response.businesses) {
        if (business.id.isNotEmpty) followedIds.add(business.id);
        if (business.publicId.isNotEmpty) followedIds.add(business.publicId);
      }
      emit(state.copyWith(followedBusinessIds: followedIds));
    } catch (_) {
      // Catalog browsing remains available if favorite status is unavailable.
    }
  }

  Future<bool> _isLocationPermissionGranted() async {
    try {
      return await _locationPermissionService.isLocationGranted();
    } catch (_) {
      return false;
    }
  }

  Future<_BusinessLoadResult> _captureBusinesses(
    Future<BusinessListApiResponse> Function() request,
  ) async {
    try {
      return _BusinessLoadResult.success(await request());
    } catch (error) {
      return _BusinessLoadResult.failure(ApiService.messageFromError(error));
    }
  }

  List<HomeBusiness> _mappedBusinesses(BusinessListApiResponse? response) {
    if (response == null) return const [];

    return response.businesses
        .where((business) => business.id.trim().isNotEmpty)
        .map(HomeBusiness.fromApi)
        .toList();
  }
}

final class _BusinessLoadResult {
  final BusinessListApiResponse? response;
  final String errorMessage;

  const _BusinessLoadResult._({this.response, this.errorMessage = ''});

  const _BusinessLoadResult.success(BusinessListApiResponse response)
    : this._(response: response);

  const _BusinessLoadResult.failure(String errorMessage)
    : this._(errorMessage: errorMessage);

  HomeSectionStatus get status =>
      response == null ? HomeSectionStatus.failure : HomeSectionStatus.ready;
}

const int _homeSectionLimit = 10;
const int _allBusinessesPageSize = 100;
const int _nearbyRadiusMeters = 25000;
