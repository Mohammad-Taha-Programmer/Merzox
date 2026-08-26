import 'package:get_it/get_it.dart';

import '../core/startup/startup_service.dart';
import '../services/push_service.dart';
import '../services/realtime_service.dart';

final locator = GetIt.instance;

Future<void> setupInjector() async {
  locator.registerLazySingleton<StartupService>(() => StartupService());
  locator.registerLazySingleton<RealtimeService>(() => RealtimeService());
  locator.registerLazySingleton<PushService>(() => PushService());
}
