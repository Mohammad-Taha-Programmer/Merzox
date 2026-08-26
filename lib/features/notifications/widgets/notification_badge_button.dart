import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/auth/auth_session_service.dart';
import '../../../injection/injector.dart';
import '../../../services/api_service.dart';
import '../../../services/realtime_service.dart';
import '../bloc/notification_badge_bloc.dart';
import '../bloc/notification_badge_event.dart';
import '../bloc/notification_badge_state.dart';

class NotificationBadgeButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String tooltip;

  final bool businessAudience;

  final double iconSize;
  final double badgeSize;
  final Color? iconColor;

  final ApiService? apiService;
  final AuthSessionService authSessionService;

  final Stream<RealtimeNotificationInvalidation>?
  realtimeNotificationInvalidations;

  final Stream<RealtimeConnectionStatus>? realtimeConnectionStatuses;

  const NotificationBadgeButton({
    super.key,
    required this.onPressed,
    required this.tooltip,
    this.businessAudience = false,
    this.iconSize = 28,
    this.badgeSize = 9,
    this.iconColor,
    this.apiService,
    this.authSessionService = const AuthSessionService(),
    this.realtimeNotificationInvalidations,
    this.realtimeConnectionStatuses,
  });

  @override
  Widget build(BuildContext context) {
    final registeredRealtime = locator.isRegistered<RealtimeService>()
        ? locator<RealtimeService>()
        : null;

    return BlocProvider(
      create: (_) => NotificationBadgeBloc(
        apiService: apiService,
        authSessionService: authSessionService,
        businessAudience: businessAudience,
        realtimeNotificationInvalidations:
            realtimeNotificationInvalidations ??
            registeredRealtime?.notificationInvalidations,
        realtimeConnectionStatuses:
            realtimeConnectionStatuses ??
            registeredRealtime?.connectionStatuses,
      )..add(const NotificationBadgeStarted()),
      child: BlocBuilder<NotificationBadgeBloc, NotificationBadgeState>(
        builder: (context, state) {
          return IconButton(
            tooltip: tooltip,
            onPressed: onPressed,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(
              minWidth: iconSize + 16,
              minHeight: iconSize + 16,
            ),
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  Icons.notifications_none_rounded,
                  size: iconSize,
                  color: iconColor,
                ),
                if (state.hasUnread)
                  PositionedDirectional(
                    top: 1,
                    end: -1,
                    child: Container(
                      key: const ValueKey('notification-unread-dot'),
                      width: badgeSize,
                      height: badgeSize,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEE6C4D),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
