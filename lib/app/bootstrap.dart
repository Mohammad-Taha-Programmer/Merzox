import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../core/startup/startup_service.dart';
import '../injection/injector.dart';
import 'app.dart';

Future<void> bootstrap() async {
  await EasyLocalization.ensureInitialized();

  await setupInjector();

  final startupService = locator<StartupService>();

  final destination = await startupService.initialize();

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
