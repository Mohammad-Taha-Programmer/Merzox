import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/services/device_location_service.dart';
import 'package:merzox/services/location_permission_service.dart';
import 'package:merzox/services/recommendation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_event.dart';
import 'home_state_.dart';

typedef HomeRecommendationSessionReader =
    Future<AuthSessionSnapshot> Function();

class HomeBloc extends Bloc<HomeEvent, HomeState> {
  final ApiService _apiService;
  final DeviceLocationService _deviceLocationService;
  final LocationPermissionService _locationPermissionService;
  final AuthSessionService _authSessionService;
  final HomeRecommendationGateway _recommendationGateway;
  final HomeRecommendationSessionReader _recommendationSessionReader;

  HomeBloc({
    ApiService? apiService,
    DeviceLocationService? deviceLocationService,
    LocationPermissionService? locationPermissionService,
    AuthSessionService authSessionService = const AuthSessionService(),
    HomeRecommendationGateway? recommendationGateway,
    HomeRecommendationSessionReader? recommendationSessionReader,
  }) : _apiService = apiService ?? ApiService(),
       _deviceLocationService =
           deviceLocationService ?? DeviceLocationService(),
       _locationPermissionService =
           locationPermissionService ?? LocationPermissionService(),
       _authSessionService = authSessionService,
       _recommendationGateway =
           recommendationGateway ?? RecommendationService(),
       _recommendationSessionReader =
           recommendationSessionReader ?? authSessionService.read,
       super(const HomeState()) {
    on<HomeStarted>(_onStarted);
    on<HomeRecommendationsRefreshRequested>(_onRecommendationsRefreshRequested);
    on<HomeRefreshRequested>(_onRefreshRequested);
    on<HomeSearchChanged>(_onSearchChanged);
    on<HomeTabChanged>(_onTabChanged);
    on<HomeLocationPromptShown>(_onLocationPromptShown);
    on<HomeLocationServiceRequested>(_onLocationServiceRequested);
    on<HomeLocationPermissionAnswered>(_onLocationPermissionAnswered);
    on<HomeBusinessFollowToggled>(_onBusinessFollowToggled);
    on<HomeAllBusinessesNextPageRequested>(_onAllBusinessesNextPageRequested);
    on<HomeAllBusinessesSearchChanged>(_onAllBusinessesSearchChanged);
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
        recommendedBusinesses: const [],
        recommendationConsentEnabled: false,
        recommendationsPersonalized: false,
        recommendationPreferenceCategories: const [],
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

    // `المتاجر` is fifty shops for a tab the reader is not looking at, and it
    // is the slowest request on the screen. It starts here with the others so
    // that tab is ready when it is opened, but the home bands are no longer
    // made to wait for it: they were, and it cost them the difference between
    // its time and theirs on every single start.
    final storesFuture = _captureBusinesses(
      () => _apiService.businesses(
        page: 1,
        limit: _allBusinessesPageSize,
        search: state.allBusinessesSearch,
        sort: 'newest',
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
    ]);

    final newest = results[0];
    final best = results[1];
    final offers = results[2];

    emit(
      state.copyWith(
        newBusinesses: _mappedBusinesses(newest.response),
        bestBusinesses: _mappedBusinesses(best.response),
        discountedBusinesses: _mappedBusinesses(offers.response),
        newBusinessesStatus: newest.status,
        bestBusinessesStatus: best.status,
        discountedBusinessesStatus: offers.status,
        newBusinessesError: newest.errorMessage,
        bestBusinessesError: best.errorMessage,
        discountedBusinessesError: offers.errorMessage,
      ),
    );

    // Three independent reads that used to run one after another, so the
    // suggestions band - which sits at the top of the screen - arrived after
    // a location fix and a favourites request it has nothing to do with.
    // Nothing here writes a field another one writes.
    final trailingFuture = Future.wait(<Future<void>>[
      if (permissionGranted) _loadNearby(emit),
      _loadFavoriteBusinesses(emit, session),
      _loadRecommendations(emit, knownSession: session),
    ]);

    final all = await storesFuture;

    emit(
      state.copyWith(
        allBusinesses: _mappedBusinesses(all.response),
        allBusinessesStatus: all.status,
        allBusinessesError: all.errorMessage,
        allBusinessesPage: all.response?.page ?? 0,
        hasMoreAllBusinesses: all.response?.hasMore ?? false,
      ),
    );

    await trailingFuture;
  }

  Future<void> _onRecommendationsRefreshRequested(
    HomeRecommendationsRefreshRequested event,
    Emitter<HomeState> emit,
  ) async {
    await _loadRecommendations(emit);
  }

  /// Everything the home screen shows, fetched again at once.
  ///
  /// A reader who pulls down has no way to name a section, so the gesture
  /// means the screen: the suggestions band, the three catalogue rows, the
  /// shops near them, and the hearts on all of it - which are as much a part
  /// of what the screen is showing as the shops themselves.
  ///
  /// `المتاجر` is not among them. It is a paged list behind its own tab with
  /// its own search field, and refetching page one of it would throw away
  /// however far a reader had scrolled in a list this gesture never touched.
  ///
  /// Nothing is put into its loading state. The indicator at the top is the
  /// progress; blanking five bands underneath it would replace a screen that
  /// is a minute old with nothing at all. For the same reason a section whose
  /// request fails keeps what it had: `copyWith` holds the old value against a
  /// null, so only that section's own failure message is raised, over content
  /// that is still standing.
  Future<void> _onRefreshRequested(
    HomeRefreshRequested event,
    Emitter<HomeState> emit,
  ) async {
    // A second pull while one is running would interleave two sets of emits.
    // The one already running is what the puller gets.
    if (state.isRefreshing) return;

    emit(state.copyWith(isRefreshing: true));

    // Started together: three requests over one link, and a screen that waited
    // for each in turn would take three times as long to say the same thing.
    final newestFuture = _captureBusinesses(
      () => _apiService.businesses(
        page: 1,
        limit: _homeSectionLimit,
        sort: 'newest',
      ),
    );
    final bestFuture = _captureBusinesses(
      () => _apiService.businesses(
        page: 1,
        limit: _homeSectionLimit,
        sort: 'rating',
      ),
    );
    final offersFuture = _captureBusinesses(
      () => _apiService.businesses(
        page: 1,
        limit: _homeSectionLimit,
        sort: 'newest',
        discounted: true,
      ),
    );

    final newest = await newestFuture;
    final best = await bestFuture;
    final offers = await offersFuture;

    emit(
      state.copyWith(
        newBusinesses: _refreshedBusinesses(newest),
        bestBusinesses: _refreshedBusinesses(best),
        discountedBusinesses: _refreshedBusinesses(offers),
        newBusinessesStatus: newest.status,
        bestBusinessesStatus: best.status,
        discountedBusinessesStatus: offers.status,
        newBusinessesError: newest.errorMessage,
        bestBusinessesError: best.errorMessage,
        discountedBusinessesError: offers.errorMessage,
      ),
    );

    await _loadNearby(emit, quiet: true);

    final session = await _authSessionService.read();
    await _loadFavoriteBusinesses(emit, session);
    await _loadRecommendations(emit, knownSession: session, quiet: true);

    // Last, and unconditionally: the screen is waiting on this to let the
    // indicator go.
    emit(state.copyWith(isRefreshing: false));
  }

  /// What a refreshed section becomes: the shops that arrived, or null.
  ///
  /// Null is the whole point. `_mappedBusinesses` answers an empty list for a
  /// request that failed, which is the right answer on a first load and the
  /// wrong one here - it would clear a band the reader was looking at because
  /// one request out of five did not come back.
  List<HomeBusiness>? _refreshedBusinesses(_BusinessLoadResult result) {
    if (result.response == null) return null;

    return _mappedBusinesses(result.response);
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

      if (state.recommendationConsentEnabled) {
        await _loadRecommendations(emit, knownSession: session);
      }
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
        // Without this, page two of a search would arrive unfiltered and be
        // merged into a filtered list.
        search: state.allBusinessesSearch,
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

  Future<void> _onAllBusinessesSearchChanged(
    HomeAllBusinessesSearchChanged event,
    Emitter<HomeState> emit,
  ) async {
    final String query = event.query.trim();
    if (query == state.allBusinessesSearch) return;

    emit(
      state.copyWith(
        allBusinessesSearch: query,
        allBusinesses: const [],
        allBusinessesPage: 0,
        hasMoreAllBusinesses: false,
        allBusinessesStatus: HomeSectionStatus.loading,
        allBusinessesError: '',
      ),
    );

    await _reloadAllBusinesses(emit);
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
        search: state.allBusinessesSearch,
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

  /// [quiet] is a refresh rather than a first load: the band keeps what it is
  /// showing while the request is in the air, and keeps it if the request
  /// fails. A reader who pulled the screen down should not be punished with an
  /// empty row for a location fix that took a moment too long.
  Future<void> _loadNearby(
    Emitter<HomeState> emit, {
    bool quiet = false,
  }) async {
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
        nearbyBusinessesStatus: quiet ? null : HomeSectionStatus.loading,
        nearbyBusinessesError: '',
      ),
    );

    try {
      if (!await _deviceLocationService.isServiceEnabled()) {
        emit(
          state.copyWith(
            nearbyBusinesses: quiet ? null : const [],
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
          nearbyBusinesses: quiet ? null : const [],
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

  /// [quiet] is a refresh rather than a first load: the band is not cleared
  /// before the request, so the suggestions the reader is looking at stay on
  /// the screen until there are new ones to put there.
  ///
  /// It is cleared the moment the answer says it should be - a reader who
  /// withdrew consent, or signed out, still sees the band emptied by the two
  /// paths below.
  Future<void> _loadRecommendations(
    Emitter<HomeState> emit, {
    AuthSessionSnapshot? knownSession,
    bool quiet = false,
  }) async {
    if (!quiet) {
      emit(
        state.copyWith(
          recommendedBusinesses: const [],
          recommendationConsentEnabled: false,
          recommendationsPersonalized: false,
          recommendationPreferenceCategories: const [],
        ),
      );
    }

    final session = knownSession ?? await _recommendationSessionReader();

    final token = session.token?.trim();

    if (!session.isAuthenticated || token == null || token.isEmpty) {
      emit(
        state.copyWith(
          recommendedBusinesses: const [],
          recommendationConsentEnabled: false,
          recommendationsPersonalized: false,
          recommendationPreferenceCategories: const [],
        ),
      );
      return;
    }

    try {
      final snapshot = await _recommendationGateway.load(token: token);

      if (!snapshot.consentEnabled) {
        // Cleared here rather than only before the request: a reader who
        // withdrew consent between two pulls would otherwise keep the band
        // they asked to stop seeing.
        emit(
          state.copyWith(
            recommendedBusinesses: const [],
            recommendationConsentEnabled: false,
            recommendationsPersonalized: false,
            recommendationPreferenceCategories: const [],
          ),
        );
        return;
      }

      emit(
        state.copyWith(
          recommendedBusinesses: snapshot.businesses
              .where((business) => business.id.trim().isNotEmpty)
              .map(HomeBusiness.fromApi)
              .toList(),
          recommendationConsentEnabled: true,
          recommendationsPersonalized: snapshot.personalized,
          recommendationPreferenceCategories: List.unmodifiable(
            snapshot.preferenceCategories,
          ),
        ),
      );
    } catch (_) {
      // Generic catalog remains available.
      // Personalized output stays cleared.
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

/// Fifty shops a page.
///
/// Large enough that scrolling rarely waits and small enough that the first
/// screen is not paid for with ninety-odd cards nobody asked for.
const int _allBusinessesPageSize = 50;
const int _nearbyRadiusMeters = 25000;
