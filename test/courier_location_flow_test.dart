import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/courier_location/courier_location_bloc.dart';
import 'package:merzox/features/courier_location/courier_location_page.dart';
import 'package:merzox/services/api_service.dart';

String get _validOrderId => List<String>.filled(24, 'a').join();

String get _validCapability => List<String>.filled(43, 'A').join();

final class _UploadCall {
  final String orderId;
  final String capabilityToken;
  final CourierLocationPoint point;

  const _UploadCall({
    required this.orderId,
    required this.capabilityToken,
    required this.point,
  });
}

final class _FakeCourierApi extends ApiService {
  final List<_UploadCall> calls = [];

  bool rejectCapability = false;

  @override
  Future<DateTime> updateCourierLocationByCapability({
    required String orderId,
    required String capabilityToken,
    required double latitude,
    required double longitude,
    required double accuracy,
    required DateTime capturedAt,
  }) async {
    if (rejectCapability) {
      throw const CourierLocationCapabilityRejected();
    }

    calls.add(
      _UploadCall(
        orderId: orderId,
        capabilityToken: capabilityToken,
        point: CourierLocationPoint(
          latitude: latitude,
          longitude: longitude,
          accuracy: accuracy,
          capturedAt: capturedAt,
        ),
      ),
    );

    return DateTime.utc(2026, 8, 27, 5, 30);
  }
}

final class _FakePositionSource implements CourierPositionSource {
  final StreamController<CourierLocationPoint> controller =
      StreamController<CourierLocationPoint>.broadcast();

  bool serviceEnabled = true;

  CourierLocationPermissionStatus permission =
      CourierLocationPermissionStatus.granted;

  CourierLocationPermissionStatus requestedPermission =
      CourierLocationPermissionStatus.granted;

  int streamRequests = 0;
  int currentPositionRequests = 0;

  @override
  Future<bool> isServiceEnabled() async => serviceEnabled;

  @override
  Future<CourierLocationPermissionStatus> checkPermission() async => permission;

  @override
  Future<CourierLocationPermissionStatus> requestPermission() async =>
      requestedPermission;

  @override
  Future<CourierLocationPoint> currentPosition() async {
    currentPositionRequests += 1;

    return CourierLocationPoint(
      latitude: 31.9038,
      longitude: 35.2034,
      accuracy: 7.5,
      capturedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Stream<CourierLocationPoint> positionStream() {
    streamRequests += 1;
    return controller.stream;
  }

  Future<void> dispose() => controller.close();
}

CourierLocationPoint get _point => CourierLocationPoint(
  latitude: 31.9038,
  longitude: 35.2034,
  accuracy: 7.5,
  capturedAt: DateTime.utc(2026, 8, 27, 5, 29, 50),
);

Future<CourierLocationState> _start(CourierLocationBloc bloc) async {
  final sharing = bloc.stream.firstWhere(
    (state) => state.status == CourierLocationStatus.sharing,
  );

  bloc.add(
    CourierLocationStartRequested(
      orderId: _validOrderId,
      capabilityToken: _validCapability,
    ),
  );

  return sharing;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'foreground lifecycle keeps inactive sessions but stops hidden/background states',
    () {
      expect(
        shouldStopCourierLocationForLifecycle(AppLifecycleState.resumed),
        isFalse,
      );

      expect(
        shouldStopCourierLocationForLifecycle(AppLifecycleState.inactive),
        isFalse,
      );

      expect(
        shouldStopCourierLocationForLifecycle(AppLifecycleState.hidden),
        isTrue,
      );

      expect(
        shouldStopCourierLocationForLifecycle(AppLifecycleState.paused),
        isTrue,
      );

      expect(
        shouldStopCourierLocationForLifecycle(AppLifecycleState.detached),
        isTrue,
      );
    },
  );

  test(
    'invalid courier credentials fail before requesting device location',
    () async {
      final api = _FakeCourierApi();
      final source = _FakePositionSource();

      final bloc = CourierLocationBloc(apiService: api, positionSource: source);

      addTearDown(() async {
        await bloc.close();
        await source.dispose();
      });

      final failed = bloc.stream.firstWhere(
        (state) => state.status == CourierLocationStatus.failure,
      );

      bloc.add(
        const CourierLocationStartRequested(
          orderId: 'bad',
          capabilityToken: 'bad',
        ),
      );

      final state = await failed;

      expect(state.errorMessage, 'courierLocation.invalidCredentials');

      expect(source.streamRequests, 0);
      expect(api.calls, isEmpty);
    },
  );

  test('denied location permission never starts the position stream', () async {
    final api = _FakeCourierApi();

    final source = _FakePositionSource()
      ..permission = CourierLocationPermissionStatus.denied
      ..requestedPermission = CourierLocationPermissionStatus.denied;

    final bloc = CourierLocationBloc(apiService: api, positionSource: source);

    addTearDown(() async {
      await bloc.close();
      await source.dispose();
    });

    final denied = bloc.stream.firstWhere(
      (state) => state.status == CourierLocationStatus.permissionDenied,
    );

    bloc.add(
      CourierLocationStartRequested(
        orderId: _validOrderId,
        capabilityToken: _validCapability,
      ),
    );

    await denied;

    expect(source.streamRequests, 0);
    expect(api.calls, isEmpty);
  });

  test(
    'foreground position is uploaded with exact order-scoped capability',
    () async {
      final api = _FakeCourierApi();
      final source = _FakePositionSource();

      final bloc = CourierLocationBloc(apiService: api, positionSource: source);

      addTearDown(() async {
        await bloc.close();
        await source.dispose();
      });

      await _start(bloc);

      final uploaded = bloc.stream.firstWhere((state) => state.hasUploaded);

      source.controller.add(_point);

      final state = await uploaded;

      expect(api.calls, hasLength(1));

      final call = api.calls.single;

      expect(call.orderId, _validOrderId);
      expect(call.capabilityToken, _validCapability);
      expect(call.point.latitude, 31.9038);
      expect(call.point.longitude, 35.2034);
      expect(call.point.accuracy, 7.5);
      expect(call.point.capturedAt, _point.capturedAt);

      expect(state.lastUploadedAt, DateTime.utc(2026, 8, 27, 5, 30));
    },
  );

  test('explicit stop cancels further location uploads', () async {
    final api = _FakeCourierApi();
    final source = _FakePositionSource();

    final bloc = CourierLocationBloc(apiService: api, positionSource: source);

    addTearDown(() async {
      await bloc.close();
      await source.dispose();
    });

    await _start(bloc);

    final uploaded = bloc.stream.firstWhere((state) => state.hasUploaded);

    source.controller.add(_point);
    await uploaded;

    final stopped = bloc.stream.firstWhere(
      (state) => state.status == CourierLocationStatus.stopped,
    );

    bloc.add(const CourierLocationStopRequested());

    await stopped;

    source.controller.add(
      CourierLocationPoint(
        latitude: 31.904,
        longitude: 35.204,
        accuracy: 5,
        capturedAt: _point.capturedAt.add(const Duration(seconds: 10)),
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(api.calls, hasLength(1));
  });

  test('capability rejection terminates the active sharing session', () async {
    final api = _FakeCourierApi()..rejectCapability = true;

    final source = _FakePositionSource();

    final bloc = CourierLocationBloc(apiService: api, positionSource: source);

    addTearDown(() async {
      await bloc.close();
      await source.dispose();
    });

    await _start(bloc);

    final failed = bloc.stream.firstWhere(
      (state) => state.status == CourierLocationStatus.failure,
    );

    source.controller.add(_point);

    final state = await failed;

    expect(state.errorMessage, 'courierLocation.capabilityRejected');
  });

  test(
    'capability response model is strict and retains only token plus expiry',
    () {
      final model = CourierLocationCapabilityApiModel.fromJson({
        'token': _validCapability,
        'expiresAt': '2026-08-27T17:00:00.000Z',
      });

      expect(model.token, _validCapability);

      expect(model.expiresAt, DateTime.utc(2026, 8, 27, 17));

      expect(
        () => CourierLocationCapabilityApiModel.fromJson({
          'token': 'bad',
          'expiresAt': '2026-08-27T17:00:00.000Z',
        }),
        throwsA(isA<ApiContractException>()),
      );
    },
  );

  test(
    'A2 source contract keeps capability out of URLs, persistence and logs',
    () {
      final router = File('lib/router/app_router.dart').readAsStringSync();

      final api = File('lib/services/api_service.dart').readAsStringSync();

      final bloc = File(
        'lib/features/courier_location/courier_location_bloc.dart',
      ).readAsStringSync();

      final page = File(
        'lib/features/courier_location/courier_location_page.dart',
      ).readAsStringSync();

      final businessShell = File(
        'lib/features/business/shell/business_shell_page.dart',
      ).readAsStringSync();

      expect(router.contains("path: '/courier/location'"), isTrue);

      expect(router.contains('/courier/location?'), isFalse);

      expect(router.contains('capabilityToken'), isFalse);

      expect(api.contains("'/orders/\$orderId/courier-location'"), isTrue);

      expect(
        api.contains("'Authorization': 'Courier \$capabilityToken'"),
        isTrue,
      );

      expect(businessShell.contains('SharePlus.instance.share'), isTrue);

      expect(businessShell.contains('Clipboard'), isFalse);

      final securitySurface = '$bloc\n$page\n$businessShell';

      expect(securitySurface.contains('SharedPreferences'), isFalse);

      expect(securitySurface.contains('flutter_secure_storage'), isFalse);

      expect(securitySurface.contains('debugPrint('), isFalse);

      expect(securitySurface.contains('print('), isFalse);

      expect(page.contains('shouldStopCourierLocationForLifecycle'), isTrue);

      expect(
        page.contains('if (!shouldStopCourierLocationForLifecycle(state))'),
        isTrue,
      );

      expect(page.contains('_capabilityController.clear()'), isTrue);
    },
  );

  test(
    'foreground heartbeat refreshes a stationary courier and stops with the session',
    () async {
      final api = _FakeCourierApi();
      final source = _FakePositionSource();

      final bloc = CourierLocationBloc(
        apiService: api,
        positionSource: source,
        heartbeatInterval: const Duration(milliseconds: 20),
      );

      addTearDown(() async {
        await bloc.close();
        await source.dispose();
      });

      await _start(bloc);

      final deadline = DateTime.now().add(const Duration(seconds: 1));

      while ((source.currentPositionRequests == 0 || api.calls.isEmpty) &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(source.currentPositionRequests, greaterThanOrEqualTo(1));

      expect(api.calls, isNotEmpty);

      final stopped = bloc.stream.firstWhere(
        (state) => state.status == CourierLocationStatus.stopped,
      );

      bloc.add(const CourierLocationStopRequested());

      await stopped;

      await Future<void>.delayed(const Duration(milliseconds: 40));

      final settled = source.currentPositionRequests;

      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(source.currentPositionRequests, settled);
    },
  );
}
