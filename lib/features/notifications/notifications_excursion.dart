import 'package:go_router/go_router.dart';

import 'widgets/global_notification_bell.dart' show currentAppLocation;

/// What the bell does to the back stack, kept apart from the app root.
///
/// Reading three notifications used to leave six screens behind it. The screen
/// a notification opens is pushed over the list it was tapped in, and the bell
/// pushed the list again over that, so each notification read cost two presses
/// of the back button to undo: a reader who had opened three was six presses
/// from the home screen, and the count grew with every one they read.
///
/// The rule here is that the whole excursion owns one place in the stack. The
/// bell remembers how deep the stack was when it was first pressed, and the
/// next press unwinds everything the excursion added before opening the list
/// again. The way back is then the same length after the third notification as
/// after the first.
///
/// It is a depth and not a location because a location cannot say how many
/// screens stand above it, and what has to be undone is a number of screens.
///
/// Pulled out of the app root because it is a decision, and a decision can be
/// stated and checked - the root itself needs a running app, a locator and a
/// startup to build at all.
class NotificationsExcursion {
  final GoRouter router;

  int? _anchorDepth;

  NotificationsExcursion(this.router);

  /// Visible so a test can state what the excursion currently believes.
  int? get anchorDepth => _anchorDepth;

  int get _stackDepth =>
      router.routerDelegate.currentConfiguration.matches.length;

  /// Forgets the anchor once the reader is back at or below it.
  ///
  /// Meant to be driven by the router's own notifications. Without it the
  /// anchor outlives the excursion: a reader who walks back out of the
  /// notification screens by hand and then opens something else entirely would
  /// find that something else closed under them the next time they reached for
  /// the bell.
  ///
  /// It only ever clears a field. The delegate notifies during its own build,
  /// and asking for a rebuild from inside that is what once put
  /// `'!_dirty': is not true` on the screen.
  void forgetAnchorOnLeaving() {
    final int? anchor = _anchorDepth;

    if (anchor != null && _stackDepth <= anchor) {
      _anchorDepth = null;
    }
  }

  /// Opens the notifications screen, closes it, or starts it over.
  ///
  /// The location is read now rather than when the bell was built: a push does
  /// not necessarily rebuild the root, and a toggle acting on a stale answer
  /// opens a second copy of the screen it meant to close.
  void toggle(String destination) {
    final String location = currentAppLocation(router);

    if (location.startsWith('/notifications')) {
      if (router.canPop()) router.pop();
      _anchorDepth = null;
      return;
    }

    final int? anchor = _anchorDepth;

    if (anchor != null && _stackDepth > anchor) {
      // `canPop` as well as the depth: the router is the authority on whether
      // anything stands under the current screen, and a loop trusting only its
      // own arithmetic is a loop that can fail to end.
      while (_stackDepth > anchor && router.canPop()) {
        router.pop();
      }
    }

    // Set on every open, not only on the first. The unwinding above walks the
    // stack back down to the anchor, which trips [forgetAnchorOnLeaving] and
    // clears it - so an excursion that only anchored when it found none would
    // re-anchor one screen too high on the next press and start growing again.
    // That is not a guess: the first version of this did exactly that, and the
    // stack grew by one for every notification read instead of two.
    _anchorDepth = _stackDepth;

    router.push(destination);
  }
}
