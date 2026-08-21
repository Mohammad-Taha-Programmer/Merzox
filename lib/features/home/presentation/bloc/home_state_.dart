import 'package:merzox/services/api_service.dart';

enum HomeSectionStatus { initial, loading, ready, failure }

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
  final HomeSectionStatus newBusinessesStatus;
  final HomeSectionStatus bestBusinessesStatus;
  final HomeSectionStatus discountedBusinessesStatus;
  final HomeSectionStatus nearbyBusinessesStatus;
  final HomeSectionStatus allBusinessesStatus;
  final String newBusinessesError;
  final String bestBusinessesError;
  final String discountedBusinessesError;
  final String nearbyBusinessesError;
  final String allBusinessesError;
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
    this.newBusinessesStatus = HomeSectionStatus.initial,
    this.bestBusinessesStatus = HomeSectionStatus.initial,
    this.discountedBusinessesStatus = HomeSectionStatus.initial,
    this.nearbyBusinessesStatus = HomeSectionStatus.initial,
    this.allBusinessesStatus = HomeSectionStatus.initial,
    this.newBusinessesError = '',
    this.bestBusinessesError = '',
    this.discountedBusinessesError = '',
    this.nearbyBusinessesError = '',
    this.allBusinessesError = '',
    this.allBusinessesPage = 0,
    this.isLoadingAllBusinesses = false,
    this.hasMoreAllBusinesses = false,
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
    HomeSectionStatus? newBusinessesStatus,
    HomeSectionStatus? bestBusinessesStatus,
    HomeSectionStatus? discountedBusinessesStatus,
    HomeSectionStatus? nearbyBusinessesStatus,
    HomeSectionStatus? allBusinessesStatus,
    String? newBusinessesError,
    String? bestBusinessesError,
    String? discountedBusinessesError,
    String? nearbyBusinessesError,
    String? allBusinessesError,
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
      newBusinessesStatus: newBusinessesStatus ?? this.newBusinessesStatus,
      bestBusinessesStatus: bestBusinessesStatus ?? this.bestBusinessesStatus,
      discountedBusinessesStatus:
          discountedBusinessesStatus ?? this.discountedBusinessesStatus,
      nearbyBusinessesStatus:
          nearbyBusinessesStatus ?? this.nearbyBusinessesStatus,
      allBusinessesStatus: allBusinessesStatus ?? this.allBusinessesStatus,
      newBusinessesError: newBusinessesError ?? this.newBusinessesError,
      bestBusinessesError: bestBusinessesError ?? this.bestBusinessesError,
      discountedBusinessesError:
          discountedBusinessesError ?? this.discountedBusinessesError,
      nearbyBusinessesError:
          nearbyBusinessesError ?? this.nearbyBusinessesError,
      allBusinessesError: allBusinessesError ?? this.allBusinessesError,
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
  final String publicId;
  final String name;
  final String englishName;
  final String category;
  final String description;
  final String address;
  final List<String> products;
  final int productCount;
  final double rating;
  final int ratingCount;
  final int followerCount;
  final int viewCount;
  final int? distanceMeters;
  final String? discount;
  final int colorValue;
  final double? latitude;
  final double? longitude;
  final DateTime? subscribedAt;

  const HomeBusiness({
    required this.id,
    this.publicId = '',
    required this.name,
    this.englishName = '',
    required this.category,
    this.description = '',
    this.address = '',
    required this.products,
    this.productCount = 0,
    required this.rating,
    this.ratingCount = 0,
    this.followerCount = 0,
    this.viewCount = 0,
    this.distanceMeters,
    this.discount,
    required this.colorValue,
    this.latitude,
    this.longitude,
    this.subscribedAt,
  });

  factory HomeBusiness.fromApi(SearchBusinessApiModel business) {
    return HomeBusiness(
      id: business.id,
      publicId: business.publicId,
      name: business.name,
      englishName: business.englishName,
      category: business.category,
      address: business.address,
      products: business.products,
      productCount: business.productCount,
      rating: business.rating,
      ratingCount: business.ratingCount,
      followerCount: business.followerCount,
      viewCount: business.viewCount,
      distanceMeters: business.distanceMeters,
      discount: business.discount,
      colorValue: business.colorValue,
      latitude: business.latitude,
      longitude: business.longitude,
      subscribedAt: business.subscribedAt,
    );
  }

  factory HomeBusiness.fromDetail(BusinessDetailApiModel business) {
    return HomeBusiness(
      id: business.id,
      publicId: business.publicId,
      name: business.name,
      englishName: business.englishName,
      category: business.category,
      description: business.description,
      address: business.address,
      products: business.products.map((product) => product.name).toList(),
      productCount: business.productCount,
      rating: business.rating,
      ratingCount: business.ratingCount,
      followerCount: business.followerCount,
      viewCount: business.viewCount,
      discount: business.discount,
      colorValue: business.colorValue,
      latitude: business.latitude,
      longitude: business.longitude,
      subscribedAt: business.subscribedAt,
    );
  }

  String get displayId => publicId.isNotEmpty ? publicId : id;

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();

    if (normalized.isEmpty) {
      return true;
    }

    return name.toLowerCase().contains(normalized) ||
        englishName.toLowerCase().contains(normalized) ||
        category.toLowerCase().contains(normalized) ||
        address.toLowerCase().contains(normalized) ||
        products.any((product) => product.toLowerCase().contains(normalized));
  }
}
