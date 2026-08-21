import '../../../services/api_service.dart';

enum NearbyMapStatus {
  initial,
  checkingPermission,
  permissionRequired,
  permissionPermanentlyDenied,
  locationServiceDisabled,
  loading,
  ready,
  failure,
}

final class NearbyMapState {
  final NearbyMapStatus status;
  final double? userLatitude;
  final double? userLongitude;
  final String query;
  final List<SearchBusinessApiModel> businesses;
  final String selectedBusinessId;
  final String errorMessage;

  const NearbyMapState({
    this.status = NearbyMapStatus.initial,
    this.userLatitude,
    this.userLongitude,
    this.query = '',
    this.businesses = const [],
    this.selectedBusinessId = '',
    this.errorMessage = '',
  });

  SearchBusinessApiModel? get selectedBusiness {
    for (final business in businesses) {
      if (business.id == selectedBusinessId) return business;
    }
    return null;
  }

  NearbyMapState copyWith({
    NearbyMapStatus? status,
    double? userLatitude,
    double? userLongitude,
    bool clearUserLocation = false,
    String? query,
    List<SearchBusinessApiModel>? businesses,
    String? selectedBusinessId,
    String? errorMessage,
  }) {
    return NearbyMapState(
      status: status ?? this.status,
      userLatitude: clearUserLocation
          ? null
          : userLatitude ?? this.userLatitude,
      userLongitude: clearUserLocation
          ? null
          : userLongitude ?? this.userLongitude,
      query: query ?? this.query,
      businesses: businesses ?? this.businesses,
      selectedBusinessId: selectedBusinessId ?? this.selectedBusinessId,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
