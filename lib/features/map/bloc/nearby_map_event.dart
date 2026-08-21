sealed class NearbyMapEvent {
  const NearbyMapEvent();
}

final class NearbyMapStarted extends NearbyMapEvent {
  const NearbyMapStarted();
}

final class NearbyMapPermissionRequested extends NearbyMapEvent {
  const NearbyMapPermissionRequested();
}

final class NearbyMapRefreshed extends NearbyMapEvent {
  const NearbyMapRefreshed();
}

final class NearbyMapSearchSubmitted extends NearbyMapEvent {
  final String query;

  const NearbyMapSearchSubmitted(this.query);
}

final class NearbyMapBusinessSelected extends NearbyMapEvent {
  final String businessId;

  const NearbyMapBusinessSelected(this.businessId);
}

final class NearbyMapAppSettingsRequested extends NearbyMapEvent {
  const NearbyMapAppSettingsRequested();
}

final class NearbyMapLocationSettingsRequested extends NearbyMapEvent {
  const NearbyMapLocationSettingsRequested();
}
