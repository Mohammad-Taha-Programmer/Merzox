import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/auth/auth_session_service.dart';
import '../../../core/constants/colors.dart';
import '../bloc/notification_badge_bloc.dart';
import '../bloc/notification_badge_event.dart';
import '../bloc/notification_badge_state.dart';

/// Where the bell sits, measured from the top-leading corner of the safe area.
///
/// It stands where the screens that had a bell already drew one, so the change
/// reads as those bells becoming permanent rather than as a new thing landing
/// on top of them.
const double kGlobalBellInset = 8;

/// How much room a top bar leaves at its trailing edge for the bell above it.
///
/// The bell floats over every screen, so a bar that fills this corner would be
/// drawn under it. The width is the icon plus its padding on both sides.
const double kGlobalBellReservedWidth = 40;

/// Routes the bell stays off.
///
/// The notifications screen itself, which it would only lead back to, and
/// everything before a session exists - there is nothing to count for someone
/// who has not signed in, and a bell over a login form is noise.
bool globalBellWantedAt(String location) {
  if (location.startsWith('/notifications')) return false;

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

  @override
  Widget build(BuildContext context) {
    return BlocProvider<NotificationBadgeBloc>(
      create: (_) =>
          (blocBuilder?.call() ??
                NotificationBadgeBloc(businessAudience: businessAudience))
            ..add(const NotificationBadgeStarted()),
      child: BlocBuilder<NotificationBadgeBloc, NotificationBadgeState>(
        builder: (BuildContext inner, NotificationBadgeState state) {
          // A white disc under it, not a colour chosen per screen. The bell
          // floats over every screen and any of them may be the same blue -
          // the merchant profile's header is exactly this one, and the bell
          // vanished into it. Fixing that screen alone would leave the next.
          return Material(
            color: Colors.white,
            shape: const CircleBorder(),
            elevation: 1,
            shadowColor: Colors.black26,
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
                      const Icon(
                        Icons.notifications_none_rounded,
                        size: 24,
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
        style: const TextStyle(
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
