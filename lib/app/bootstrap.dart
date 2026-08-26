import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../core/startup/startup_service.dart';
import '../injection/injector.dart';
import '../services/push_service.dart';
import '../services/realtime_service.dart';
import 'app.dart';

Future<void> bootstrap() async {
  await EasyLocalization.ensureInitialized();

  await setupInjector();

  final pushService = locator<PushService>();

  // If Remember Me was explicitly disabled, unregister while the previous
  // process' bearer token is still available. StartupService may purge it next.
  await pushService.prepareForStartup();

  final startupService = locator<StartupService>();

  final destination = await startupService.initialize();

  // StartupService resolves cold-start session truth first. Only then may
  // realtime authenticate, so an intentionally non-remembered session is
  // never revived by the socket layer.
  await locator<RealtimeService>().syncWithSession();

  // Push follows the same resolved authenticated session truth. The service is
  // disabled by default until production Firebase platform config exists.
  await pushService.syncWithSession();

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('ar')],
      path: 'assets/translations',
      fallbackLocale: const Locale('ar'),
      startLocale: const Locale('ar'),
      child: MerzoxApp(destination: destination),
    ),
  );
}
