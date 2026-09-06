import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../injection/injector.dart';
import '../../../services/realtime_service.dart';
import '../../notifications/widgets/global_notification_bell.dart';
import '../bloc/message_badge_bloc.dart';

/// Puts the waiting-conversation count on a messages icon.
///
/// Wraps whatever icon a screen already draws rather than replacing it: the
/// customer's lives in the bottom bar and the merchant's in the top one, and
/// they are different sizes and colours. What they share is that neither said
/// anything - four people waiting looked exactly like none.
///
/// The count itself is [UnreadCountBadge], the same one the notification bell
/// wears, so two counts on one screen cannot come to look like two different
/// kinds of thing.
class MessageBadge extends StatelessWidget {
  final Widget child;

  /// Whether this counts the shop's conversations or the reader's own.
  final bool businessAudience;

  /// Injected by tests, which have no service locator and no socket.
  final MessageBadgeBloc Function()? blocBuilder;

  const MessageBadge({
    required this.child,
    required this.businessAudience,
    this.blocBuilder,
    super.key,
  });

  MessageBadgeBloc _bloc() {
    final RealtimeService? realtime = locator.isRegistered<RealtimeService>()
        ? locator<RealtimeService>()
        : null;

    return MessageBadgeBloc(
      businessAudience: businessAudience,
      realtimeMessageInvalidations: realtime?.messageInvalidations,
      realtimeConnectionStatuses: realtime?.connectionStatuses,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<MessageBadgeBloc>(
      create: (_) =>
          (blocBuilder?.call() ?? _bloc())..add(const MessageBadgeStarted()),
      child: BlocBuilder<MessageBadgeBloc, MessageBadgeState>(
        builder: (BuildContext _, MessageBadgeState state) {
          return Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              child,
              if (state.unreadCount > 0)
                PositionedDirectional(
                  // On the shoulder, clear of the glyph, exactly as the bell
                  // wears its own count.
                  top: -6,
                  end: -6,
                  child: UnreadCountBadge(count: state.unreadCount),
                ),
            ],
          );
        },
      ),
    );
  }
}
