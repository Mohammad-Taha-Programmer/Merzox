import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/map/bloc/nearby_map_bloc.dart';
import 'package:merzox/features/map/bloc/nearby_map_event.dart';
import 'package:merzox/features/map/bloc/nearby_map_state.dart';
import 'package:merzox/features/map/pages/nearby_map_page.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/services/device_location_service.dart';
import 'package:merzox/services/location_permission_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'golden/merzox_golden_harness.dart';

/// `الخريطة` at the device viewport.
///
/// COVERAGE.md recorded this page as one that "never finishes" a frame at
/// 375x812, which is why it is the single board with no golden seed. That was
/// measured wrongly: the page renders. What never finished was `bloc.close()`
/// in teardown after a pump inside `runAsync` - the same thing that made the
/// storefront look unrenderable, and which the golden seeds already work
/// around by not awaiting the close.
///
/// This pins the states that do render, so the claim is a test rather than a
/// paragraph. The fully-ready map with its tile layer is still not captured,
/// and that is stated in COVERAGE.md rather than implied by silence here.

class _NoNearbyApi extends ApiService {
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
  }) async => BusinessListApiResponse.fromJson(const <String, dynamic>{
    'businesses': <Map<String, dynamic>>[],
    'pagination': <String, dynamic>{
      'page': 1,
      'limit': 20,
      'total': 0,
      'hasMore': false,
    },
  });
}

final class _PermissionDenied extends LocationPermissionService {
  @override
  Future<bool> isLocationGranted() async => false;
}

final class _ServiceOff extends DeviceLocationService {
  @override
  Future<bool> isServiceEnabled() async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
    await loadMerzoxGoldenDateSymbols();
    await loadMerzoxGoldenFonts();
  });

  testWidgets('the map asks for location at the device viewport', (
    WidgetTester tester,
  ) async {
    final NearbyMapBloc bloc = NearbyMapBloc(
      apiService: _NoNearbyApi(),
      deviceLocationService: _ServiceOff(),
      permissionService: _PermissionDenied(),
    );
    // Not awaited: awaiting it is what hangs, and what this file exists to
    // correct the record about.
    addTearDown(() => unawaited(bloc.close()));

    final Future<NearbyMapState> settled = bloc.stream.firstWhere(
      (NearbyMapState state) => state.status != NearbyMapStatus.loading,
    );
    bloc.add(const NearbyMapStarted());
    await settled;

    await pumpMerzoxGoldenPage(
      tester,
      BlocProvider<NearbyMapBloc>.value(
        value: bloc,
        child: withMerzoxGoldenDeviceInsets(const NearbyMapPage()),
      ),
    );

    // The page drew, at 375x812, which the record said it could not do.
    expect(find.text('الخريطة'), findsOneWidget);
    expect(find.text('فعّل الموقع لعرض المتاجر القريبة'), findsOneWidget);
    expect(find.text('السماح بالموقع'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
