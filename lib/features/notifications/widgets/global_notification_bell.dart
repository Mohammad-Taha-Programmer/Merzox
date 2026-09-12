import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_session_service.dart';
import '../../../core/constants/colors.dart';
import '../../../core/widgets/merzox_icons.dart';
import '../../../injection/injector.dart';
import '../../../services/realtime_service.dart';
import '../bloc/notification_badge_bloc.dart';
import '../bloc/notification_badge_event.dart';
import '../bloc/notification_badge_state.dart';

/// Where the bell sits, measured from the top-leading corner of the safe area.
///
/// It stands where the screens that had a bell already drew one, so the change
/// reads as those bells becoming permanent rather than as a new thing landing
/// on top of them.
const double kGlobalBellInset = 8;

/// How tall the bell's tap target is: its glyph, and the padding around it.
///
/// Stated rather than measured at runtime so a bar can line its own icons up
/// with the bell before either is laid out.
const double kGlobalBellDiameter =
    kGlobalBellInset * 2 + 24 * MerzoxIcons.notificationsSizeFactor;

/// Where the bell's middle sits, measured down from the top of the safe area.
///
/// A bar that wants its icons on the bell's line puts their centres here. The
/// merchant's bar did not, and drew them fourteen pixels below the customer's:
/// the three controls in that corner sat on two different lines until the
/// reader scrolled and two of them left.
const double kGlobalBellCentreFromSafeAreaTop =
    kGlobalBellInset + kGlobalBellDiameter / 2;

/// How much room a top bar leaves at its trailing edge for the bell above it.
///
/// The bell floats over every screen, so a bar that fills this corner would be
/// drawn under it. The width is the icon plus its padding on both sides.
const double kGlobalBellReservedWidth = 40;

/// Where the app is, read safely.
///
/// Three readings and only one is right in both moments this needs. The route
/// information provider carries the initial location but never moves for a
/// `push`, so a toggle built on it always sees the screen it opened from.
/// `GoRouter.state` does follow a push - and throws `Bad state: No element`
/// before the first route is resolved, which the framework paints as a red
/// screen on launch. So: the state, once there is one.
String currentAppLocation(GoRouter router) {
  if (router.routerDelegate.currentConfiguration.isEmpty) {
    return router.routeInformationProvider.value.uri.toString();
  }

  return router.state.uri.toString();
}

/// Routes the bell stays off.
///
/// Everything before a session exists: there is nothing to count for someone
/// who has not signed in, and a bell over a login form is noise.
///
/// The notifications screen is deliberately not among them. The bell is how
/// that screen is opened and how it is closed again, so it has to be reachable
/// while it is showing.
bool globalBellWantedAt(String location) {
  const List<String> silent = <String>[
    '/login',
    '/signup',
    '/onboarding',
    '/splash',
    '/business/login',
    '/business/enroll',
    '/password',
    '/verify',
  ];

  return !silent.any(location.startsWith);
}

/// Hangs the bell over whatever the router is showing.
///
/// It listens to the router rather than reading it. That distinction is the
/// whole of this widget: the app's own `builder` used to decide from
/// [currentAppLocation] without subscribing to anything, so the answer it gave
/// was whichever one it had when it last ran for some unrelated reason. A
/// reader signed in, arrived at a home screen with no bell on it, and the bell
/// appeared when they pressed the language toggle - because changing the
/// locale is what finally rebuilt the app root.
///
/// The delegate is what it listens to, not the route information provider:
/// that provider carries the initial location and does not move for a `push`,
/// and a `push` is how the bell opens the very screen it has to stay reachable
/// from.
class GlobalBellOverlay extends StatefulWidget {
  final GoRouter router;

  /// The router's own subtree, which this hangs the bell over.
  final Widget child;

  /// Builds the bell. Passed in so this widget owns the following and the
  /// placing, and nothing else.
  final WidgetBuilder bellBuilder;

  const GlobalBellOverlay({
    super.key,
    required this.router,
    required this.child,
    required this.bellBuilder,
  });

  @override
  State<GlobalBellOverlay> createState() => _GlobalBellOverlayState();
}

class _GlobalBellOverlayState extends State<GlobalBellOverlay> {
  late bool _wanted = globalBellWantedAt(currentAppLocation(widget.router));

  @override
  void initState() {
    super.initState();
    widget.router.routerDelegate.addListener(_followRouter);
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_followRouter);
    super.dispose();
  }

  /// Re-reads where the app is, after the frame that moved it.
  ///
  /// After, not during. This widget is built inside the router's own build, so
  /// the delegate's notification arrives while this element is being built and
  /// marking it dirty then trips `'!_dirty': is not true` - which is a red
  /// screen, not a missing bell. A `ListenableBuilder` here does exactly that.
  void _followRouter() {
    final bool wanted = globalBellWantedAt(currentAppLocation(widget.router));
    if (wanted == _wanted) return;

    final SchedulerPhase phase = SchedulerBinding.instance.schedulerPhase;
    final bool building =
        phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks;

    if (!building) {
      setState(() => _wanted = wanted);
      return;
    }

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bool now = globalBellWantedAt(currentAppLocation(widget.router));
      if (now == _wanted) return;
      setState(() => _wanted = now);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        widget.child,
        if (_wanted)
          PositionedDirectional(
            top: MediaQuery.paddingOf(context).top + kGlobalBellInset,
            // The trailing edge, which right-to-left is the left: where every
            // bar that had a bell already drew one. The leading edge is where
            // the account's picture lives.
            end: kGlobalBellInset,
            child: widget.bellBuilder(context),
          ),
      ],
    );
  }
}

/// The one bell, floating over whatever screen is showing.
///
/// Every screen used to draw its own, and several drew none - so a merchant
/// deep in a product editor could take an order and have no way to know. There
/// is one now, mounted once above the router, and it follows the reader rather
/// than the screen.
///
/// It counts rather than dots. A dot says only that something happened; a
/// merchant deciding whether to stop what they are doing needs to know whether
/// it is one order or nine.
///
/// Being above the router costs it the router: there is no `GoRouter` in its
/// context, so `context.push` throws. Navigation is handed in instead, which
/// also means this widget knows where it wants to go without knowing how.
class GlobalNotificationBell extends StatelessWidget {
  /// Whether the signed-in account reads the shop's notifications or their own.
  final bool businessAudience;

  /// Opens the location the bell decided on.
  ///
  /// Supplied by the app root, which holds the router this widget sits above.
  final void Function(String location) onOpen;

  /// Injected by tests, which have no service locator.
  final NotificationBadgeBloc Function()? blocBuilder;

  const GlobalNotificationBell({
    required this.businessAudience,
    required this.onOpen,
    this.blocBuilder,
    super.key,
  });

  /// Where a tap goes. Named so it can be stated in a test.
  String get destination =>
      businessAudience ? '/notifications?audience=business' : '/notifications';

  /// The badge the bell wears, wired to the socket that feeds it.
  ///
  /// Without the two streams the count is read once, when the bell is first
  /// built, and never again: a merchant taking an order saw nothing until they
  /// restarted the app, and reading a notification left the number where it
  /// was. Both symptoms were the same omission - the bloc was constructed with
  /// its audience and nothing else, so it subscribed to nothing.
  ///
  /// The service is read through the locator rather than passed down, because
  /// this widget hangs above the router and there is no provider tree over it.
  /// A missing registration is tolerated rather than thrown on: a bell that
  /// counts only on open is poor, and one that crashes the app root is worse.
  NotificationBadgeBloc _createBloc() {
    final NotificationBadgeBloc? supplied = blocBuilder?.call();

    if (supplied != null) return supplied;

    final RealtimeService? realtime = locator.isRegistered<RealtimeService>()
        ? locator<RealtimeService>()
        : null;

    return NotificationBadgeBloc(
      businessAudience: businessAudience,
      realtimeNotificationInvalidations: realtime?.notificationInvalidations,
      realtimeConnectionStatuses: realtime?.connectionStatuses,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<NotificationBadgeBloc>(
      create: (_) => _createBloc()..add(const NotificationBadgeStarted()),
      child: BlocBuilder<NotificationBadgeBloc, NotificationBadgeState>(
        builder: (BuildContext inner, NotificationBadgeState state) {
          // A white disc under it, not a colour chosen per screen. The bell
          // floats over every screen and any of them may be the same blue -
          // the merchant profile's header is exactly this one, and the bell
          // vanished into it. Fixing that screen alone would leave the next.
          //
          // The disc is flat, though. It used to carry a shadow, which on the
          // two home screens - both of them white - was the only thing the
          // disc drew at all: a faint ring around a bell that had nothing to
          // stand out from, making it read as a button sitting on top of the
          // screen rather than a mark on it. The disc stays because the blue
          // header still needs it; the lift does not.
          return Material(
            color: Colors.white,
            shape: const CircleBorder(),
            elevation: 0,
            child: InkWell(
              key: const ValueKey<String>('merzox.globalBell'),
              customBorder: const CircleBorder(),
              onTap: () => onOpen(destination),
              // A `Semantics` label rather than a `Tooltip`, deliberately.
              // This is mounted above the router, outside the Navigator that
              // owns the app's Overlay, and a tooltip without one throws on
              // build - which painted a red screen over the whole app. This
              // names the control for a screen reader and needs nothing.
              child: Semantics(
                button: true,
                label: 'notifications.title'.tr(),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      // The size it drew at as a Material bell, converted.
                      Icon(
                        MerzoxIcons.globalBellNotifications,
                        size: 24 * MerzoxIcons.notificationsSizeFactor,
                        color: MerzoxColors.kColor98C1D9,
                      ),
                      if (state.unreadCount > 0)
                        PositionedDirectional(
                          // On the shoulder, clear of the glyph: a wide count
                          // anchored level with it crosses the bell body.
                          top: -9,
                          end: -8,
                          child: UnreadCountBadge(count: state.unreadCount),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// How many are waiting.
///
/// Past ninety-nine it reads `99+`: the exact number stops being a number
/// anyone acts on, and a four-digit badge would be wider than the bell.
class UnreadCountBadge extends StatelessWidget {
  final int count;

  const UnreadCountBadge({required this.count, super.key});

  static const int max = 99;

  @override
  Widget build(BuildContext context) {
    final String label = count > max ? '$max+' : '$count';

    return Container(
      key: const ValueKey<String>('merzox.unreadCount'),
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: MerzoxColors.kColorEE6C4D,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Text(
        label,
        // Never wrapped and never clipped: a count that reads `1` when it
        // means `12` is worse than no count.
        maxLines: 1,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        // The family is named rather than inherited. The count is dropped onto
        // whatever icon a screen already draws, and one of those may sit where
        // no `DefaultTextStyle` reaches - and the digits then render as empty
        // boxes, so the badge says nothing at all.
        style: const TextStyle(
          fontFamily: 'Tajawal',
          color: Colors.white,
          fontSize: 9,
          height: 1.1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Resolves whose notifications the bell is counting.
///
/// The session decides it, not the screen: a merchant browsing the customer
/// side of the app is still the person whose shop takes the orders.
class GlobalBellAudience extends StatefulWidget {
  final Widget Function(BuildContext context, bool businessAudience) builder;
  final AuthSessionService sessionService;

  const GlobalBellAudience({
    required this.builder,
    this.sessionService = const AuthSessionService(),
    super.key,
  });

  @override
  State<GlobalBellAudience> createState() => _GlobalBellAudienceState();
}

class _GlobalBellAudienceState extends State<GlobalBellAudience> {
  bool? _businessAudience;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    final AuthSessionSnapshot session = await widget.sessionService.read();
    if (!mounted) return;

    setState(() {
      _businessAudience = session.isAuthenticated ? session.isBusiness : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Nothing until it is known who is reading: a bell counting the wrong
    // side's notifications is worse than a bell that arrives a frame late.
    if (_businessAudience case final bool audience) {
      return widget.builder(context, audience);
    }

    return const SizedBox.shrink();
  }
}
