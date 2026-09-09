import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:merzox/core/constants/dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/core/widgets/merzox_icons.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/core/localization/api_error_localizer.dart';

import '../bloc/notifications_bloc.dart';
import '../notification_destination.dart';
import '../notifications_visibility.dart';
import '../bloc/notifications_event.dart';
import '../bloc/notifications_state.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final ScrollController _scrollController = ScrollController();

  /// Whether the reader asked past the default fifty.
  ///
  /// Held here rather than in the bloc: the bloc knows what the server sent,
  /// and this is a question about how much of it this screen is showing.
  bool _showingAll = false;

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

    final String? destination = notificationDestination(
      notification,
      businessAudience: context.read<NotificationsBloc>().businessAudience,
    );

    if (destination != null) context.push(destination);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: BlocConsumer<NotificationsBloc, NotificationsState>(
          // A read-state write that the server refused is reported here rather
          // than left to look like it succeeded.
          listenWhen: (previous, current) =>
              previous.errorMessage != current.errorMessage,
          listener: (context, state) {
            if (state.errorMessage.isEmpty) return;
            if (state.status == NotificationsStatus.failure) return;

            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(localizeApiErrorOrRaw(state.errorMessage)),
                ),
              );
          },
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
                : localizeApiErrorOrRaw(state.errorMessage),
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
          // 56 / 0.835, the bell's ink filling less of its em box.
          const Icon(
            MerzoxIcons.notifications,
            size: 67,
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

    final DateTime now = DateTime.now();
    final List<AppNotificationApiModel> shown = visibleNotifications(
      state.notifications,
      now: now,
      showingAll: _showingAll,
    );
    final bool heldBack = notificationsAreHeldBack(
      state.notifications,
      now: now,
      showingAll: _showingAll,
      serverHasMore: state.hasMore,
    );
    final bool loadingMore = state.status == NotificationsStatus.loadingMore;

    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(11, 8, 11, 24),
      itemCount: shown.length + (heldBack || loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= shown.length) {
          if (loadingMore) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: TextButton(
                key: const ValueKey<String>('notifications.showMore'),
                onPressed: _showMore,
                child: Text(
                  'notifications.showMore'.tr(),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: MerzoxColors.kColor3D5A80,
                  ),
                ),
              ),
            ),
          );
        }

        final notification = shown[index];
        return NotificationTile(
          notification: notification,
          onTap: () => _open(notification),
        );
      },
    );
  }

  /// Opens what the default view was holding back.
  ///
  /// The screen's own limit is lifted first; only once everything already
  /// fetched is on show is the server asked for the next page.
  void _showMore() {
    if (!_showingAll) {
      setState(() => _showingAll = true);
      return;
    }

    context.read<NotificationsBloc>().add(
      const NotificationsLoadMoreRequested(),
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

/// One notification, as a box.
///
/// Public so a test can find it: the screen is otherwise a list of anonymous
/// containers, and what is under test is how one of these reads.
class NotificationTile extends StatelessWidget {
  final AppNotificationApiModel notification;
  final VoidCallback onTap;

  const NotificationTile({
    required this.notification,
    required this.onTap,
    super.key,
  });

  /// The box's fill, and its border.
  ///
  /// The border is the same colour as the fill on purpose: the box is meant to
  /// read as one soft shape, not as an outlined card.
  static const Color _fill = MerzoxColors.kColorB9DDF3;

  @override
  Widget build(BuildContext context) {
    final bool unread = !notification.isRead;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.all(5),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _fill.withValues(alpha: 0.7),
            border: Border.all(color: _fill.withValues(alpha: 0.7)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  notification.body.isEmpty
                      ? notification.title
                      : '${notification.title} · ${notification.body}',
                  // No `maxLines` and no ellipsis: a notification cut off at
                  // `...` is one a reader has to open to understand, and the
                  // box has no fixed height to protect any more.
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    fontWeight: unread ? FontWeight.w700 : FontWeight.w400,
                    color: MerzoxColors.kColor3B3B3B,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  _formatTimestamp(notification.createdAt),
                  style: const TextStyle(
                    fontSize: 11,
                    color: MerzoxColors.kColor5E5E5E,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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

  return '${merzoxDay(local)} , $time';
}
