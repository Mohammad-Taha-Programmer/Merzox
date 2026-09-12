import 'package:merzox/features/notifications/widgets/global_notification_bell.dart';
import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/startup/startup_destination.dart';
import '../features/notifications/notifications_excursion.dart';
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

    // Plain bookkeeping, no rebuild: the delegate notifies during its own
    // build, and asking for one from here is what put `'!_dirty': is not true`
    // on the screen the last time something listened to it.
    _router.routerDelegate.addListener(_forgetAnchorOnLeaving);

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

    _router.routerDelegate.removeListener(_forgetAnchorOnLeaving);

    _router.dispose();

    super.dispose();
  }

  /// What the bell does to the back stack. See [NotificationsExcursion].
  late final NotificationsExcursion _notifications = NotificationsExcursion(
    _router,
  );

  void _forgetAnchorOnLeaving() => _notifications.forgetAnchorOnLeaving();

  void _toggleNotifications(String destination) =>
      _notifications.toggle(destination);

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
      // The bell is mounted once, here, above every route. Each screen used to
      // draw its own and several drew none, so a merchant deep in a product
      // editor could take an order and have no way to know.
      builder: (BuildContext context, Widget? child) {
        return GlobalBellOverlay(
          router: _router,
          child: child ?? const SizedBox.shrink(),
          bellBuilder: (BuildContext _) => GlobalBellAudience(
            builder: (BuildContext _, bool businessAudience) =>
                GlobalNotificationBell(
                  businessAudience: businessAudience,
                  // The router itself, not `context.push`: this hangs above
                  // the router, so there is none in its context.
                  onOpen: _toggleNotifications,
                ),
          ),
        );
      },
    );
  }
}
