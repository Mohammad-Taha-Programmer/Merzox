import 'package:geolocator/geolocator.dart';

class DeviceLocation {
  final double latitude;
  final double longitude;

  const DeviceLocation({required this.latitude, required this.longitude});
}

class DeviceLocationService {
  Future<bool> isServiceEnabled() {
    return Geolocator.isLocationServiceEnabled();
  }

  Future<DeviceLocation> currentLocation() async {
    Position? position = await Geolocator.getLastKnownPosition();

    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (_) {
      if (position == null) rethrow;
    }

    return DeviceLocation(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }

  Future<bool> openLocationSettings() {
    return Geolocator.openLocationSettings();
  }
}
