import 'package:get_it/get_it.dart';

import '../core/startup/startup_service.dart';

final locator = GetIt.instance;

Future<void> setupInjector() async {
  locator.registerLazySingleton<StartupService>(() => StartupService());
}
