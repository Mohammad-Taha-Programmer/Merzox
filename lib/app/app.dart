import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/startup/startup_destination.dart';
import '../injection/injector.dart';
import '../router/app_router.dart';
import '../services/push_service.dart';

class MerzoxApp extends StatefulWidget {
  final StartupDestination destination;

  const MerzoxApp({super.key, required this.destination});

  @override
  State<MerzoxApp> createState() => _MerzoxAppState();
}

class _MerzoxAppState extends State<MerzoxApp> {
  late final GoRouter _router;

  StreamSubscription<PushTapIntent>? _pushTapSubscription;

  @override
  void initState() {
    super.initState();

    // Keep one router for the app-root lifetime. Locale rebuilds must not
    // recreate navigation state or push subscriptions.
    _router = AppRouter(widget.destination).router;

    if (locator.isRegistered<PushService>()) {
      final pushService = locator<PushService>();

      _pushTapSubscription = pushService.tapIntents.listen(_handlePushTap);

      // Subscribe before getInitialMessage() can be consumed.
      unawaited(pushService.startTapHandling());
    }
  }

  void _handlePushTap(PushTapIntent intent) {
    // AppRouter/AuthRouteGuard still decides whether this destination is
    // permitted for the current authenticated session.
    _router.go(intent.location);
  }

  @override
  void dispose() {
    unawaited(_pushTapSubscription?.cancel());

    _router.dispose();

    super.dispose();
  }

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
      routerConfig: _router,
    );
  }
}
