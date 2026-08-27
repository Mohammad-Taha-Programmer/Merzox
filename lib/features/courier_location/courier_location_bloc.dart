import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';

import '../../services/api_service.dart';

enum CourierLocationPermissionStatus { granted, denied, deniedForever }

final class CourierLocationPoint {
  final double latitude;
  final double longitude;
  final double accuracy;
  final DateTime capturedAt;

  const CourierLocationPoint({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.capturedAt,
  });
}

abstract interface class CourierPositionSource {
  Future<bool> isServiceEnabled();

  Future<CourierLocationPermissionStatus> checkPermission();

  Future<CourierLocationPermissionStatus> requestPermission();

  Future<CourierLocationPoint> currentPosition();

  Stream<CourierLocationPoint> positionStream();
}

final class GeolocatorCourierPositionSource implements CourierPositionSource {
  const GeolocatorCourierPositionSource();

  CourierLocationPermissionStatus _mapPermission(
    LocationPermission permission,
  ) {
    if (permission == LocationPermission.deniedForever) {
      return CourierLocationPermissionStatus.deniedForever;
    }

    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      return CourierLocationPermissionStatus.granted;
    }

    return CourierLocationPermissionStatus.denied;
  }

  @override
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<CourierLocationPermissionStatus> checkPermission() async {
    return _mapPermission(await Geolocator.checkPermission());
  }

  @override
  Future<CourierLocationPermissionStatus> requestPermission() async {
    return _mapPermission(await Geolocator.requestPermission());
  }

  @override
  Future<CourierLocationPoint> currentPosition() async {
    const settings = LocationSettings(accuracy: LocationAccuracy.high);

    final position = await Geolocator.getCurrentPosition(
      locationSettings: settings,
    );

    return CourierLocationPoint(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      capturedAt: position.timestamp,
    );
  }

  @override
  Stream<CourierLocationPoint> positionStream() {
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 20,
    );

    return Geolocator.getPositionStream(locationSettings: settings).map(
      (position) => CourierLocationPoint(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        capturedAt: position.timestamp,
      ),
    );
  }
}

sealed class CourierLocationEvent {
  const CourierLocationEvent();
}

final class CourierLocationStartRequested extends CourierLocationEvent {
  final String orderId;
  final String capabilityToken;

  const CourierLocationStartRequested({
    required this.orderId,
    required this.capabilityToken,
  });
}

final class CourierLocationStopRequested extends CourierLocationEvent {
  const CourierLocationStopRequested();
}

final class _CourierLocationPointObserved extends CourierLocationEvent {
  final CourierLocationPoint point;
  final int generation;

  const _CourierLocationPointObserved(this.point, this.generation);
}

final class _CourierLocationSourceFailed extends CourierLocationEvent {
  final String message;
  final int generation;

  const _CourierLocationSourceFailed(this.message, this.generation);
}

enum CourierLocationStatus {
  initial,
  checking,
  sharing,
  stopped,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  failure,
}

final class CourierLocationState {
  final CourierLocationStatus status;
  final bool hasUploaded;
  final DateTime? lastUploadedAt;
  final String errorMessage;

  const CourierLocationState({
    this.status = CourierLocationStatus.initial,
    this.hasUploaded = false,
    this.lastUploadedAt,
    this.errorMessage = '',
  });

  bool get isActive =>
      status == CourierLocationStatus.checking ||
      status == CourierLocationStatus.sharing;
}

class CourierLocationBloc
    extends Bloc<CourierLocationEvent, CourierLocationState> {
  final ApiService _apiService;
  final CourierPositionSource _positionSource;

  StreamSubscription<CourierLocationPoint>? _positionSubscription;
  Timer? _heartbeatTimer;

  final Duration _heartbeatInterval;

  String? _activeOrderId;
  String? _activeCapabilityToken;

  CourierLocationPoint? _queuedPoint;

  bool _uploadInFlight = false;

  int _generation = 0;

  CourierLocationBloc({
    ApiService? apiService,
    CourierPositionSource positionSource =
        const GeolocatorCourierPositionSource(),
    Duration heartbeatInterval = const Duration(minutes: 5),
  }) : assert(heartbeatInterval.inMilliseconds > 0),
       _apiService = apiService ?? ApiService(),
       _positionSource = positionSource,
       _heartbeatInterval = heartbeatInterval,
       super(const CourierLocationState()) {
    on<CourierLocationStartRequested>(_onStartRequested);
    on<CourierLocationStopRequested>(_onStopRequested);
    on<_CourierLocationPointObserved>(_onPointObserved);
    on<_CourierLocationSourceFailed>(_onSourceFailed);
  }

  Future<void> _onStartRequested(
    CourierLocationStartRequested event,
    Emitter<CourierLocationState> emit,
  ) async {
    if (state.isActive) {
      return;
    }

    final orderId = event.orderId.trim();
    final capabilityToken = event.capabilityToken.trim();

    if (!RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(orderId) ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(capabilityToken)) {
      emit(
        const CourierLocationState(
          status: CourierLocationStatus.failure,
          errorMessage: 'courierLocation.invalidCredentials',
        ),
      );
      return;
    }

    await _stopActiveSession();

    emit(const CourierLocationState(status: CourierLocationStatus.checking));

    try {
      if (!await _positionSource.isServiceEnabled()) {
        emit(
          const CourierLocationState(
            status: CourierLocationStatus.serviceDisabled,
          ),
        );
        return;
      }

      var permission = await _positionSource.checkPermission();

      if (permission == CourierLocationPermissionStatus.denied) {
        permission = await _positionSource.requestPermission();
      }

      if (permission == CourierLocationPermissionStatus.deniedForever) {
        emit(
          const CourierLocationState(
            status: CourierLocationStatus.permissionDeniedForever,
          ),
        );
        return;
      }

      if (permission != CourierLocationPermissionStatus.granted) {
        emit(
          const CourierLocationState(
            status: CourierLocationStatus.permissionDenied,
          ),
        );
        return;
      }

      _activeOrderId = orderId;
      _activeCapabilityToken = capabilityToken;

      final generation = _generation;

      _positionSubscription = _positionSource.positionStream().listen(
        (point) {
          add(_CourierLocationPointObserved(point, generation));
        },
        onError: (Object error, StackTrace stackTrace) {
          add(
            _CourierLocationSourceFailed(
              ApiService.messageFromError(error),
              generation,
            ),
          );
        },
      );

      _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
        unawaited(_captureHeartbeat(generation));
      });

      emit(const CourierLocationState(status: CourierLocationStatus.sharing));
    } catch (error) {
      await _stopActiveSession();

      emit(
        CourierLocationState(
          status: CourierLocationStatus.failure,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  Future<void> _captureHeartbeat(int generation) async {
    if (generation != _generation ||
        state.status != CourierLocationStatus.sharing ||
        _activeOrderId == null ||
        _activeCapabilityToken == null) {
      return;
    }

    try {
      final point = await _positionSource.currentPosition();

      if (generation != _generation ||
          state.status != CourierLocationStatus.sharing ||
          _activeOrderId == null ||
          _activeCapabilityToken == null) {
        return;
      }

      add(_CourierLocationPointObserved(point, generation));
    } catch (_) {
      // Supplemental heartbeat failure is non-fatal.
      // The foreground stream remains primary and no secret is logged.
    }
  }

  Future<void> _onStopRequested(
    CourierLocationStopRequested event,
    Emitter<CourierLocationState> emit,
  ) async {
    final hasUploaded = state.hasUploaded;
    final lastUploadedAt = state.lastUploadedAt;

    await _stopActiveSession();

    emit(
      CourierLocationState(
        status: CourierLocationStatus.stopped,
        hasUploaded: hasUploaded,
        lastUploadedAt: lastUploadedAt,
      ),
    );
  }

  Future<void> _onPointObserved(
    _CourierLocationPointObserved event,
    Emitter<CourierLocationState> emit,
  ) async {
    if (event.generation != _generation ||
        state.status != CourierLocationStatus.sharing ||
        _activeOrderId == null ||
        _activeCapabilityToken == null) {
      return;
    }

    if (_uploadInFlight) {
      _queuedPoint = event.point;
      return;
    }

    _uploadInFlight = true;

    CourierLocationPoint? current = event.point;

    try {
      while (current != null &&
          event.generation == _generation &&
          _activeOrderId != null &&
          _activeCapabilityToken != null) {
        try {
          final receivedAt = await _apiService
              .updateCourierLocationByCapability(
                orderId: _activeOrderId!,
                capabilityToken: _activeCapabilityToken!,
                latitude: current.latitude,
                longitude: current.longitude,
                accuracy: current.accuracy,
                capturedAt: current.capturedAt,
              );

          if (event.generation != _generation) {
            return;
          }

          emit(
            CourierLocationState(
              status: CourierLocationStatus.sharing,
              hasUploaded: true,
              lastUploadedAt: receivedAt,
            ),
          );
        } on CourierLocationCapabilityRejected {
          final hadUploaded = state.hasUploaded;
          final lastUploadedAt = state.lastUploadedAt;

          await _stopActiveSession();

          emit(
            CourierLocationState(
              status: CourierLocationStatus.failure,
              hasUploaded: hadUploaded,
              lastUploadedAt: lastUploadedAt,
              errorMessage: 'courierLocation.capabilityRejected',
            ),
          );
          return;
        } catch (error) {
          if (event.generation != _generation) {
            return;
          }

          emit(
            CourierLocationState(
              status: CourierLocationStatus.sharing,
              hasUploaded: state.hasUploaded,
              lastUploadedAt: state.lastUploadedAt,
              errorMessage: ApiService.messageFromError(error),
            ),
          );
        }

        if (event.generation != _generation) {
          return;
        }

        current = _queuedPoint;
        _queuedPoint = null;
      }
    } finally {
      if (event.generation == _generation) {
        _uploadInFlight = false;
      }
    }
  }

  Future<void> _onSourceFailed(
    _CourierLocationSourceFailed event,
    Emitter<CourierLocationState> emit,
  ) async {
    if (event.generation != _generation) {
      return;
    }

    final hasUploaded = state.hasUploaded;
    final lastUploadedAt = state.lastUploadedAt;

    await _stopActiveSession();

    emit(
      CourierLocationState(
        status: CourierLocationStatus.failure,
        hasUploaded: hasUploaded,
        lastUploadedAt: lastUploadedAt,
        errorMessage: event.message,
      ),
    );
  }

  Future<void> _stopActiveSession() async {
    _generation += 1;

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    await _positionSubscription?.cancel();

    _positionSubscription = null;
    _activeOrderId = null;
    _activeCapabilityToken = null;
    _queuedPoint = null;
    _uploadInFlight = false;
  }

  @override
  Future<void> close() async {
    await _stopActiveSession();
    return super.close();
  }
}
