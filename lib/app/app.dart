import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../core/startup/startup_destination.dart';
import '../router/app_router.dart';

class MerzoxApp extends StatelessWidget {
  final StartupDestination destination;

  const MerzoxApp({super.key, required this.destination});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Merzox',
      locale: context.locale,
      supportedLocales: context.supportedLocales,
      localizationsDelegates: context.localizationDelegates,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3D5A80)),
        fontFamily: 'Tajawal',
        useMaterial3: true,
      ),
      routerConfig: AppRouter(destination).router,
    );
  }
}
