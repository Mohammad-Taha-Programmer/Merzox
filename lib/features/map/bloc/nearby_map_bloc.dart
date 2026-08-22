import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/api_service.dart';
import '../../../services/device_location_service.dart';
import '../../../services/location_permission_service.dart';
import '../../../core/auth/auth_session_service.dart';
import '../../authentication/bloc/auth_bloc.dart';
import 'nearby_map_event.dart';
import 'nearby_map_state.dart';

class NearbyMapBloc extends Bloc<NearbyMapEvent, NearbyMapState> {
  final ApiService _apiService;
  final AuthSessionService _authSessionService;
  final DeviceLocationService _deviceLocationService;
  final LocationPermissionService _permissionService;

  NearbyMapBloc({
    ApiService? apiService,
    DeviceLocationService? deviceLocationService,
    LocationPermissionService? permissionService,
    AuthSessionService authSessionService = const AuthSessionService(),
  }) : _apiService = apiService ?? ApiService(),
       _authSessionService = authSessionService,
       _deviceLocationService =
           deviceLocationService ?? DeviceLocationService(),
       _permissionService = permissionService ?? LocationPermissionService(),
       super(const NearbyMapState()) {
    on<NearbyMapStarted>(_onStarted);
    on<NearbyMapPermissionRequested>(_onPermissionRequested);
    on<NearbyMapRefreshed>(_onRefreshed);
    on<NearbyMapSearchSubmitted>(_onSearchSubmitted);
    on<NearbyMapBusinessSelected>(_onBusinessSelected);
    on<NearbyMapAppSettingsRequested>(_onAppSettingsRequested);
    on<NearbyMapLocationSettingsRequested>(_onLocationSettingsRequested);
  }

  Future<void> _onStarted(
    NearbyMapStarted event,
    Emitter<NearbyMapState> emit,
  ) async {
    emit(state.copyWith(status: NearbyMapStatus.checkingPermission));
    final granted = await _permissionService.isLocationGranted();
    if (!granted) {
      emit(state.copyWith(status: NearbyMapStatus.permissionRequired));
      return;
    }

    await _loadNearby(emit, refreshPosition: true);
  }

  Future<void> _onPermissionRequested(
    NearbyMapPermissionRequested event,
    Emitter<NearbyMapState> emit,
  ) async {
    emit(state.copyWith(status: NearbyMapStatus.checkingPermission));
    final permission = await _permissionService.requestLocation();

    if (permission == MerzoxLocationPermissionStatus.permanentlyDenied ||
        permission == MerzoxLocationPermissionStatus.restricted) {
      await _syncPermission(false);
      emit(state.copyWith(status: NearbyMapStatus.permissionPermanentlyDenied));
      return;
    }

    if (permission != MerzoxLocationPermissionStatus.granted) {
      await _syncPermission(false);
      emit(state.copyWith(status: NearbyMapStatus.permissionRequired));
      return;
    }

    await _syncPermission(true);
    await _loadNearby(emit, refreshPosition: true);
  }

  Future<void> _onRefreshed(
    NearbyMapRefreshed event,
    Emitter<NearbyMapState> emit,
  ) async {
    final granted = await _permissionService.isLocationGranted();
    if (!granted) {
      emit(state.copyWith(status: NearbyMapStatus.permissionRequired));
      return;
    }
    await _loadNearby(emit, refreshPosition: true);
  }

  Future<void> _onSearchSubmitted(
    NearbyMapSearchSubmitted event,
    Emitter<NearbyMapState> emit,
  ) async {
    final query = event.query.trim();
    emit(state.copyWith(query: query, selectedBusinessId: ''));
    await _loadNearby(emit, refreshPosition: state.userLatitude == null);
  }

  void _onBusinessSelected(
    NearbyMapBusinessSelected event,
    Emitter<NearbyMapState> emit,
  ) {
    emit(state.copyWith(selectedBusinessId: event.businessId));
  }

  Future<void> _onAppSettingsRequested(
    NearbyMapAppSettingsRequested event,
    Emitter<NearbyMapState> emit,
  ) async {
    await _permissionService.openAppSettingsPage();
  }

  Future<void> _onLocationSettingsRequested(
    NearbyMapLocationSettingsRequested event,
    Emitter<NearbyMapState> emit,
  ) async {
    await _deviceLocationService.openLocationSettings();
  }

  Future<void> _loadNearby(
    Emitter<NearbyMapState> emit, {
    required bool refreshPosition,
  }) async {
    emit(state.copyWith(status: NearbyMapStatus.loading, errorMessage: ''));

    try {
      if (!await _deviceLocationService.isServiceEnabled()) {
        emit(state.copyWith(status: NearbyMapStatus.locationServiceDisabled));
        return;
      }

      var latitude = state.userLatitude;
      var longitude = state.userLongitude;
      if (refreshPosition || latitude == null || longitude == null) {
        final location = await _deviceLocationService.currentLocation();
        latitude = location.latitude;
        longitude = location.longitude;
      }

      final response = await _apiService.businesses(
        latitude: latitude,
        longitude: longitude,
        radiusMeters: 25000,
        search: state.query,
        limit: 100,
      );
      final businesses = response.businesses
          .where(
            (business) =>
                business.latitude != null && business.longitude != null,
          )
          .toList();

      emit(
        state.copyWith(
          status: NearbyMapStatus.ready,
          userLatitude: latitude,
          userLongitude: longitude,
          businesses: businesses,
          selectedBusinessId:
              businesses.any(
                (business) => business.id == state.selectedBusinessId,
              )
              ? state.selectedBusinessId
              : '',
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: NearbyMapStatus.failure,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  Future<void> _syncPermission(bool granted) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AuthBloc.locationPermissionGrantedKey, granted);
    await prefs.setBool(AuthBloc.locationPromptPendingKey, false);

    final userId = prefs.getString(AuthBloc.userIdKey);
    if (userId != null && userId.isNotEmpty) {
      await prefs.setBool('${AuthBloc.locationPromptAskedPrefix}$userId', true);
    }

    // The location keys above are UI state and stay in preferences; the
    // bearer token for this protected call does not.
    final session = await _authSessionService.read();
    final token = session.token;
    if (token == null) return;

    try {
      await _apiService.updatePermissions(token: token, location: granted);
    } catch (_) {
      // The operating-system permission remains authoritative while offline.
    }
  }
}
