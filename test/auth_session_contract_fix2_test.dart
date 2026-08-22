import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/business/enrollment/business_enrollment_bloc.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/features/favorites/bloc/favorites_bloc.dart';
import 'package:merzox/features/favorites/bloc/favorites_event.dart';
import 'package:merzox/features/favorites/bloc/favorites_state.dart';
import 'package:merzox/features/map/bloc/nearby_map_bloc.dart';
import 'package:merzox/features/map/bloc/nearby_map_event.dart';
import 'package:merzox/features/map/bloc/nearby_map_state.dart';
import 'package:merzox/features/orders/bloc/orders_bloc.dart';
import 'package:merzox/features/orders/bloc/orders_event.dart';
import 'package:merzox/features/orders/bloc/orders_state.dart';
import 'package:merzox/features/profile/bloc/profile_edit_bloc.dart';
import 'package:merzox/features/profile/bloc/profile_edit_event.dart';
import 'package:merzox/features/profile/bloc/profile_edit_state.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/services/device_location_service.dart';
import 'package:merzox/services/location_permission_service.dart';

import 'auth_session_fixtures.dart';

/// FIX2-A: the five BLoCs that still read the stored token directly are now on
/// the same centralized contract as the messaging/notification/tracking ones.
/// Each is driven through the three stored-session shapes, and the assertion
/// that matters is that the spy recorded ZERO protected calls for a stale or
/// blank session.
class _SpyApi extends ApiService {
  final List<String> calls = [];

  @override
  Future<OrderListApiResponse> orders({
    required String token,
    required String status,
    int page = 1,
    int limit = 20,
  }) async {
    calls.add('orders');
    return OrderListApiResponse.fromJson(const {});
  }

  @override
  Future<FavoriteBusinessListApiResponse> favoriteBusinesses({
    required String token,
    int page = 1,
    int limit = 20,
  }) async {
    calls.add('favoriteBusinesses');
    return FavoriteBusinessListApiResponse.fromJson(const {});
  }

  @override
  Future<AuthApiUser> me({required String token}) async {
    calls.add('me');
    return AuthApiUser.fromJson(const {
      'id': 'u1',
      'name': 'Test',
      'userType': 'normal',
      'gender': 'unspecified',
      'address': '',
    });
  }

  @override
  Future<AuthApiUser> updatePermissions({
    required String token,
    bool? location,
    bool? aiPersonalization,
    bool? contacts,
  }) async {
    calls.add('updatePermissions');
    return AuthApiUser.fromJson(const {
      'id': 'u1',
      'name': 'Test',
      'userType': 'normal',
      'gender': 'unspecified',
      'address': '',
    });
  }

  @override
  Future<BusinessEnrollmentResult> enrollBusiness({
    required String token,
    required String phone,
    required String email,
    required String currentPassword,
    required String name,
    required String englishName,
    required String description,
    required String category,
    required String address,
    required String attachmentUrl,
  }) async {
    calls.add('enrollBusiness');
    return BusinessEnrollmentResult.fromJson(const {
      'business': {'id': 'b1', 'name': 'Store'},
    });
  }

  /// The nearby map's catalog read is public, so it must keep working for a
  /// signed-out visitor. It is deliberately not recorded as a protected call.
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
    return BusinessListApiResponse.fromJson(const {});
  }
}

class _GrantedPermissionService extends LocationPermissionService {
  @override
  Future<bool> isLocationGranted() async => true;

  @override
  Future<MerzoxLocationPermissionStatus> requestLocation() async =>
      MerzoxLocationPermissionStatus.granted;
}

class _FixedLocationService extends DeviceLocationService {
  @override
  Future<bool> isServiceEnabled() async => true;

  @override
  Future<DeviceLocation> currentLocation() async =>
      const DeviceLocation(latitude: 31.9, longitude: 35.2);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> runContract({
    required String label,
    required Future<bool> Function(_SpyApi api) attempt,
  }) async {
    useStaleTokenWithoutSession();
    final staleApi = _SpyApi();
    final staleReached = await attempt(staleApi);
    expect(
      staleApi.calls,
      isEmpty,
      reason: '$label: a logged-out token must not reach the API',
    );
    expect(
      staleReached,
      isFalse,
      reason: '$label: stale token must not succeed',
    );

    useBlankTokenSession();
    final blankApi = _SpyApi();
    final blankReached = await attempt(blankApi);
    expect(
      blankApi.calls,
      isEmpty,
      reason: '$label: a blank token must not reach the API',
    );
    expect(
      blankReached,
      isFalse,
      reason: '$label: blank token must not succeed',
    );

    useAuthenticatedSession();
    final liveApi = _SpyApi();
    final liveReached = await attempt(liveApi);
    expect(
      liveApi.calls,
      isNotEmpty,
      reason: '$label: a real session must reach the API',
    );
    expect(liveReached, isTrue, reason: '$label: real session must succeed');
  }

  test('OrdersBloc honours the centralized session contract', () async {
    await runContract(
      label: 'OrdersBloc',
      attempt: (api) async {
        final bloc = OrdersBloc(apiService: api);
        bloc.add(const OrdersStarted());
        final state = await bloc.stream.firstWhere(
          (s) =>
              s.status == OrdersStatus.ready ||
              s.status == OrdersStatus.failure,
        );
        await bloc.close();
        return state.status == OrdersStatus.ready;
      },
    );
  });

  test('FavoritesBloc honours the centralized session contract', () async {
    await runContract(
      label: 'FavoritesBloc',
      attempt: (api) async {
        final bloc = FavoritesBloc(apiService: api);
        bloc.add(const FavoritesStarted());
        final state = await bloc.stream.firstWhere(
          (s) =>
              s.status == FavoritesStatus.ready ||
              s.status == FavoritesStatus.failure,
        );
        await bloc.close();
        return state.status == FavoritesStatus.ready;
      },
    );
  });

  test('ProfileEditBloc honours the centralized session contract', () async {
    await runContract(
      label: 'ProfileEditBloc',
      attempt: (api) async {
        final bloc = ProfileEditBloc(apiService: api);
        bloc.add(const ProfileEditStarted());
        final state = await bloc.stream.firstWhere(
          (s) =>
              s.status == ProfileEditStatus.ready ||
              s.status == ProfileEditStatus.failure,
        );
        await bloc.close();
        return state.status == ProfileEditStatus.ready;
      },
    );
  });

  test(
    'BusinessEnrollmentBloc honours the centralized session contract',
    () async {
      await runContract(
        label: 'BusinessEnrollmentBloc',
        attempt: (api) async {
          final bloc = BusinessEnrollmentBloc(apiService: api);
          bloc
            ..add(
              const BusinessEnrollmentFirstStepSaved(
                phone: '+972590000001',
                email: 'merchant@example.test',
                password: 'Password123',
              ),
            )
            ..add(
              const BusinessEnrollmentSubmitted(
                name: 'متجر',
                englishName: 'Store',
                description: 'desc',
                category: 'Groceries',
                address: 'رام الله',
                attachmentUrl: '',
              ),
            );
          final state = await bloc.stream.firstWhere(
            (s) =>
                s.status == BusinessEnrollmentStatus.success ||
                s.status == BusinessEnrollmentStatus.failure,
          );
          await bloc.close();
          return state.status == BusinessEnrollmentStatus.success;
        },
      );
    },
  );

  group('NearbyMapBloc', () {
    /// The map's catalog read is public, so the contract here is narrower:
    /// the protected permission sync must not fire without a real session,
    /// while the public map itself keeps working either way.
    Future<_SpyApi> requestPermission() async {
      final api = _SpyApi();
      final bloc = NearbyMapBloc(
        apiService: api,
        deviceLocationService: _FixedLocationService(),
        permissionService: _GrantedPermissionService(),
      );

      bloc.add(const NearbyMapPermissionRequested());
      await bloc.stream.firstWhere(
        (s) =>
            s.status != NearbyMapStatus.checkingPermission &&
            s.status != NearbyMapStatus.initial,
      );
      await bloc.close();
      return api;
    }

    test('a stale token does not sync permissions', () async {
      useStaleTokenWithoutSession();
      final api = await requestPermission();
      expect(api.calls, isEmpty);
    });

    test('a blank token does not sync permissions', () async {
      useBlankTokenSession();
      final api = await requestPermission();
      expect(api.calls, isEmpty);
    });

    test('a real session syncs the permission', () async {
      useAuthenticatedSession();
      final api = await requestPermission();
      expect(api.calls, contains('updatePermissions'));
    });
  });
}
