import 'package:get_it/get_it.dart';

import '../core/startup/startup_service.dart';
import '../features/notifications/notifications_session_store.dart';
import '../services/push_service.dart';
import '../services/realtime_service.dart';

final locator = GetIt.instance;

Future<void> setupInjector() async {
  locator.registerLazySingleton<StartupService>(() => StartupService());
  locator.registerLazySingleton<RealtimeService>(() => RealtimeService());
  locator.registerLazySingleton<PushService>(() => PushService());

  // The notification feed, for as long as the app is open. A singleton because
  // it has to be the same list whichever screen asks for it, and a singleton in
  // a process that ends is a cache that clears itself.
  locator.registerLazySingleton<NotificationsSessionStore>(
    () => NotificationsSessionStore(),
  );
}
