import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/services/api_service.dart';

import '../bloc/notifications_bloc.dart';
import '../bloc/notifications_event.dart';
import '../bloc/notifications_state.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < 240) {
      context.read<NotificationsBloc>().add(
        const NotificationsLoadMoreRequested(),
      );
    }
  }

  /// Every notification carries the ids needed to reach the thing it is about,
  /// so tapping one lands on that order or conversation instead of a dead end.
  void _open(AppNotificationApiModel notification) {
    context.read<NotificationsBloc>().add(
      NotificationMarkedRead(notification.id),
    );

    switch (notification.type) {
      case 'newMessage':
        if (notification.conversationId.isNotEmpty) {
          context.push(
            Uri(
              path: '/chat',
              queryParameters: {
                'conversationId': notification.conversationId,
                'title': notification.title,
              },
            ).toString(),
          );
        }
      case 'orderPlaced':
      case 'orderStatus':
      case 'orderCancelled':
        if (notification.orderId.isNotEmpty) {
          context.push('/orders/${notification.orderId}/tracking');
        }
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: BlocBuilder<NotificationsBloc, NotificationsState>(
          builder: (context, state) {
            return Column(
              children: [
                _NotificationsHeader(unreadCount: state.unreadCount),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async => context
                        .read<NotificationsBloc>()
                        .add(const NotificationsRefreshRequested()),
                    child: _buildBody(context, state),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, NotificationsState state) {
    if (state.status == NotificationsStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.status == NotificationsStatus.failure) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 120),
        children: [
          const Icon(
            Icons.wifi_off_rounded,
            size: 44,
            color: MerzoxColors.kColor8D99AE,
          ),
          const SizedBox(height: 12),
          Text(
            state.errorMessage.isEmpty
                ? 'notifications.loadError'.tr()
                : state.errorMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MerzoxColors.kColor5E5E5E,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton(
              onPressed: () => context.read<NotificationsBloc>().add(
                const NotificationsRefreshRequested(),
              ),
              child: Text('common.retry'.tr()),
            ),
          ),
        ],
      );
    }

    if (state.notifications.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 120),
        children: [
          const Icon(
            Icons.notifications_none_rounded,
            size: 56,
            color: MerzoxColors.kColorBEBEBE,
          ),
          const SizedBox(height: 18),
          Text(
            'notifications.emptyTitle'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MerzoxColors.kColor2B2B2B,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'notifications.emptyHint'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MerzoxColors.kColor767676,
              fontSize: 13,
              height: 1.6,
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount:
          state.notifications.length +
          (state.status == NotificationsStatus.loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= state.notifications.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final notification = state.notifications[index];
        return _NotificationTile(
          notification: notification,
          onTap: () => _open(notification),
        );
      },
    );
  }
}

class _NotificationsHeader extends StatelessWidget {
  final int unreadCount;

  const _NotificationsHeader({required this.unreadCount});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 66,
      child: Row(
        children: [
          const BackButton(color: MerzoxColors.kColor5E5E5E),
          Expanded(
            child: Text(
              'notifications.title'.tr(),
              style: const TextStyle(
                color: MerzoxColors.kColor2B2B2B,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (unreadCount > 0)
            TextButton(
              onPressed: () => context.read<NotificationsBloc>().add(
                const NotificationsAllMarkedRead(),
              ),
              child: Text(
                'notifications.markAllRead'.tr(),
                style: const TextStyle(
                  color: MerzoxColors.kColorEE6C4D,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotificationApiModel notification;
  final VoidCallback onTap;

  const _NotificationTile({required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final unread = !notification.isRead;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: unread ? MerzoxColors.kColorFDF1EC : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: unread
                  ? MerzoxColors.kColorFEE3DC
                  : MerzoxColors.kColorEFEFEF,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: unread
                      ? MerzoxColors.kColorEE6C4D
                      : MerzoxColors.kColorDEEEF8,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _iconFor(notification.type),
                  size: 20,
                  color: unread ? Colors.white : MerzoxColors.kColor3D5A80,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: MerzoxColors.kColor2B2B2B,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.body,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        color: MerzoxColors.kColor767676,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _formatTimestamp(notification.createdAt),
                      style: const TextStyle(
                        fontSize: 9,
                        color: MerzoxColors.kColor8D99AE,
                      ),
                    ),
                  ],
                ),
              ),
              if (unread)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: const BoxDecoration(
                    color: MerzoxColors.kColorEE6C4D,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _iconFor(String type) {
  return switch (type) {
    'orderPlaced' => Icons.receipt_long_rounded,
    'orderStatus' => Icons.local_shipping_rounded,
    'orderCancelled' => Icons.cancel_outlined,
    'newMessage' => Icons.chat_bubble_rounded,
    'newReview' => Icons.star_rounded,
    _ => Icons.notifications_rounded,
  };
}

String _formatTimestamp(DateTime? value) {
  if (value == null) return '';

  final local = value.toLocal();
  final now = DateTime.now();
  final isToday =
      local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;

  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final suffix = local.hour >= 12 ? 'PM' : 'AM';
  final time = '$hour:$minute $suffix';

  if (isToday) return time;

  return '${local.day}.${local.month}.${local.year} , $time';
}
