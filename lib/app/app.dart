import 'package:merzox/features/notifications/widgets/global_notification_bell.dart';
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

  /// The bell opens the notifications screen, and closes it again.
  ///
  /// The location is read when the bell is tapped rather than when it was
  /// built: a push does not necessarily rebuild this, and a toggle that acts
  /// on a stale answer opens a second copy of the screen it meant to close.
  void _toggleNotifications(String destination) {
    final String location = currentAppLocation(_router);

    if (location.startsWith('/notifications')) {
      if (_router.canPop()) _router.pop();
      return;
    }

    _router.push(destination);
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
      // The bell is mounted once, here, above every route. Each screen used to
      // draw its own and several drew none, so a merchant deep in a product
      // editor could take an order and have no way to know.
      builder: (BuildContext context, Widget? child) {
        return Stack(
          children: <Widget>[
            child ?? const SizedBox.shrink(),
            if (globalBellWantedAt(currentAppLocation(_router)))
              PositionedDirectional(
                top: MediaQuery.paddingOf(context).top + kGlobalBellInset,
                // The trailing edge, which right-to-left is the left: where
                // every bar that had a bell already drew one. The leading edge
                // is where the account's picture lives.
                end: kGlobalBellInset,
                child: GlobalBellAudience(
                  builder: (BuildContext _, bool businessAudience) =>
                      GlobalNotificationBell(
                        businessAudience: businessAudience,
                        // The router itself, not `context.push`: this hangs
                        // above the router, so there is none in its context.
                        onOpen: _toggleNotifications,
                      ),
                ),
              ),
          ],
        );
      },
    );
  }
}
