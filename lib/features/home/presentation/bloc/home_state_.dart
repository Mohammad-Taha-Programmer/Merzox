final class HomeState {
  final String searchQuery;
  final int selectedTab;
  final bool shouldAskLocationPermission;
  final bool locationPermissionHandled;
  final bool locationPermissionGranted;
  final bool locationPermissionPermanentlyDenied;
  final String locationPermissionReason;
  final List<HomeBusiness> newBusinesses;
  final List<HomeBusiness> bestBusinesses;
  final List<HomeBusiness> discountedBusinesses;
  final List<HomeBusiness> nearbyBusinesses;
  final List<HomeBusiness> allBusinesses;
  final int allBusinessesPage;
  final bool isLoadingAllBusinesses;
  final bool hasMoreAllBusinesses;
  final Set<String> followedBusinessIds;

  const HomeState({
    this.searchQuery = '',
    this.selectedTab = 0,
    this.shouldAskLocationPermission = false,
    this.locationPermissionHandled = false,
    this.locationPermissionGranted = false,
    this.locationPermissionPermanentlyDenied = false,
    this.locationPermissionReason = 'firstLogin',
    this.newBusinesses = const [],
    this.bestBusinesses = const [],
    this.discountedBusinesses = const [],
    this.nearbyBusinesses = const [],
    this.allBusinesses = const [],
    this.allBusinessesPage = 0,
    this.isLoadingAllBusinesses = false,
    this.hasMoreAllBusinesses = true,
    this.followedBusinessIds = const {},
  });

  HomeState copyWith({
    String? searchQuery,
    int? selectedTab,
    bool? shouldAskLocationPermission,
    bool? locationPermissionHandled,
    bool? locationPermissionGranted,
    bool? locationPermissionPermanentlyDenied,
    String? locationPermissionReason,
    List<HomeBusiness>? newBusinesses,
    List<HomeBusiness>? bestBusinesses,
    List<HomeBusiness>? discountedBusinesses,
    List<HomeBusiness>? nearbyBusinesses,
    List<HomeBusiness>? allBusinesses,
    int? allBusinessesPage,
    bool? isLoadingAllBusinesses,
    bool? hasMoreAllBusinesses,
    Set<String>? followedBusinessIds,
  }) {
    return HomeState(
      searchQuery: searchQuery ?? this.searchQuery,
      selectedTab: selectedTab ?? this.selectedTab,
      shouldAskLocationPermission:
          shouldAskLocationPermission ?? this.shouldAskLocationPermission,
      locationPermissionHandled:
          locationPermissionHandled ?? this.locationPermissionHandled,
      locationPermissionGranted:
          locationPermissionGranted ?? this.locationPermissionGranted,
      locationPermissionPermanentlyDenied:
          locationPermissionPermanentlyDenied ??
          this.locationPermissionPermanentlyDenied,
      locationPermissionReason:
          locationPermissionReason ?? this.locationPermissionReason,
      newBusinesses: newBusinesses ?? this.newBusinesses,
      bestBusinesses: bestBusinesses ?? this.bestBusinesses,
      discountedBusinesses: discountedBusinesses ?? this.discountedBusinesses,
      nearbyBusinesses: nearbyBusinesses ?? this.nearbyBusinesses,
      allBusinesses: allBusinesses ?? this.allBusinesses,
      allBusinessesPage: allBusinessesPage ?? this.allBusinessesPage,
      isLoadingAllBusinesses:
          isLoadingAllBusinesses ?? this.isLoadingAllBusinesses,
      hasMoreAllBusinesses: hasMoreAllBusinesses ?? this.hasMoreAllBusinesses,
      followedBusinessIds: followedBusinessIds ?? this.followedBusinessIds,
    );
  }
}

final class HomeBusiness {
  final String id;
  final String name;
  final String category;
  final List<String> products;
  final double rating;
  final String distance;
  final String? discount;
  final int colorValue;

  const HomeBusiness({
    required this.id,
    required this.name,
    required this.category,
    required this.products,
    required this.rating,
    required this.distance,
    this.discount,
    required this.colorValue,
  });

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();

    if (normalized.isEmpty) {
      return true;
    }

    return name.toLowerCase().contains(normalized) ||
        category.toLowerCase().contains(normalized) ||
        products.any((product) => product.toLowerCase().contains(normalized));
  }
}
