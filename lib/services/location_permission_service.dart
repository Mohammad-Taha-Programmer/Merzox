import 'package:permission_handler/permission_handler.dart';

enum MerzoxLocationPermissionStatus {
  granted,
  denied,
  permanentlyDenied,
  restricted,
}

class LocationPermissionService {
  Future<bool> isLocationGranted() async {
    return Permission.locationWhenInUse.isGranted;
  }

  Future<MerzoxLocationPermissionStatus> requestLocation() async {
    final status = await Permission.locationWhenInUse.request();

    if (status.isGranted || status.isLimited) {
      return MerzoxLocationPermissionStatus.granted;
    }

    if (status.isPermanentlyDenied) {
      return MerzoxLocationPermissionStatus.permanentlyDenied;
    }

    if (status.isRestricted) {
      return MerzoxLocationPermissionStatus.restricted;
    }

    return MerzoxLocationPermissionStatus.denied;
  }

  Future<bool> openAppSettingsPage() => openAppSettings();
}
