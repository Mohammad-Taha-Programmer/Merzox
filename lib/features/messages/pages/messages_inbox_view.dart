import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/core/localization/api_error_localizer.dart';

import '../bloc/messages_bloc.dart';
import '../bloc/messages_event.dart';
import '../bloc/messages_state.dart';

/// The inbox from the design: an "all / unread" pair of tabs over a list of
/// threads. It is shared by the customer tab and the merchant shell, which
/// differ only in the bloc they are given.
class MessagesInboxView extends StatefulWidget {
  final String title;
  final EdgeInsets padding;
  final bool showTitle;

  const MessagesInboxView({
    super.key,
    required this.title,
    this.padding = const EdgeInsets.fromLTRB(16, 18, 16, 118),
    this.showTitle = true,
  });

  @override
  State<MessagesInboxView> createState() => _MessagesInboxViewState();
}

class _MessagesInboxViewState extends State<MessagesInboxView> {
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
      context.read<MessagesBloc>().add(const MessagesLoadMoreRequested());
    }
  }

  Future<void> _openThread(ConversationApiModel conversation) async {
    final bloc = context.read<MessagesBloc>();

    await context.push(
      Uri(
        path: '/chat',
        queryParameters: {
          'conversationId': conversation.id,
          'title': conversation.title,
          'avatarUrl': conversation.avatarUrl,
        },
      ).toString(),
    );

    if (!mounted) return;
    // The backend owns the unread state. Zeroing it locally here would claim a
    // read receipt that ChatBloc may have failed to persist, so the inbox is
    // simply re-read and whatever the server reports wins.
    bloc.add(const MessagesRefreshRequested());
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MessagesBloc, MessagesState>(
      builder: (context, state) {
        return RefreshIndicator(
          onRefresh: () async => context.read<MessagesBloc>().add(
            const MessagesRefreshRequested(),
          ),
          child: ListView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: widget.padding,
            children: [
              if (widget.showTitle)
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: MerzoxColors.kColor2B2B2B,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              const SizedBox(height: 14),
              _InboxTabs(
                filter: state.filter,
                unreadCount: state.unreadConversationCount,
              ),
              const SizedBox(height: 18),
              ..._buildBody(context, state),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildBody(BuildContext context, MessagesState state) {
    if (state.status == MessagesStatus.loading) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: 140),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    if (state.status == MessagesStatus.failure) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 100),
          child: Column(
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                size: 44,
                color: MerzoxColors.kColor8D99AE,
              ),
              const SizedBox(height: 12),
              Text(
                state.errorMessage.isEmpty
                    ? 'messages.loadError'.tr()
                    : localizeApiErrorOrRaw(state.errorMessage),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: MerzoxColors.kColor5E5E5E,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => context.read<MessagesBloc>().add(
                  const MessagesRefreshRequested(),
                ),
                child: Text('common.retry'.tr()),
              ),
            ],
          ),
        ),
      ];
    }

    if (state.conversations.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 90),
          child: Column(
            children: [
              const Icon(
                Icons.forum_outlined,
                size: 56,
                color: MerzoxColors.kColorBEBEBE,
              ),
              const SizedBox(height: 18),
              Text(
                state.filter == MessagesFilter.unread
                    ? 'messages.emptyUnreadTitle'.tr()
                    : 'messages.emptyTitle'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: MerzoxColors.kColor2B2B2B,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                state.filter == MessagesFilter.unread
                    ? 'messages.emptyUnreadHint'.tr()
                    : 'messages.emptyHint'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: MerzoxColors.kColor767676,
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ];
    }

    return [
      for (final conversation in state.conversations)
        _ConversationTile(
          conversation: conversation,
          onTap: () => _openThread(conversation),
        ),
      if (state.status == MessagesStatus.loadingMore)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(child: CircularProgressIndicator()),
        ),
    ];
  }
}

class _InboxTabs extends StatelessWidget {
  final MessagesFilter filter;
  final int unreadCount;

  const _InboxTabs({required this.filter, required this.unreadCount});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _InboxTab(
          label: 'messages.tabUnread'.tr(),
          badge: unreadCount,
          selected: filter == MessagesFilter.unread,
          onTap: () => context.read<MessagesBloc>().add(
            const MessagesFilterChanged(MessagesFilter.unread),
          ),
        ),
        const SizedBox(width: 22),
        _InboxTab(
          label: 'messages.tabAll'.tr(),
          badge: 0,
          selected: filter == MessagesFilter.all,
          onTap: () => context.read<MessagesBloc>().add(
            const MessagesFilterChanged(MessagesFilter.all),
          ),
        ),
      ],
    );
  }
}

class _InboxTab extends StatelessWidget {
  final String label;
  final int badge;
  final bool selected;
  final VoidCallback onTap;

  const _InboxTab({
    required this.label,
    required this.badge,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: selected
                        ? MerzoxColors.kColor2B2B2B
                        : MerzoxColors.kColor8D99AE,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
                if (badge > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: MerzoxColors.kColorEE6C4D,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$badge',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 5),
            Container(
              height: 2,
              width: 26,
              decoration: BoxDecoration(
                color: selected
                    ? MerzoxColors.kColorEE6C4D
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final ConversationApiModel conversation;
  final VoidCallback onTap;

  const _ConversationTile({required this.conversation, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: MerzoxColors.kColorEFEFEF),
          ),
          child: Row(
            children: [
              _InboxAvatar(
                url: conversation.avatarUrl,
                label: conversation.title,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conversation.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: conversation.hasUnread
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: MerzoxColors.kColor2B2B2B,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      conversation.lastMessage.body.isEmpty
                          ? 'messages.noMessagesYet'.tr()
                          : conversation.lastMessage.body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: conversation.hasUnread
                            ? MerzoxColors.kColor3B3B3B
                            : MerzoxColors.kColor767676,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatTimestamp(
                      conversation.lastMessage.sentAt,
                      context.locale.toLanguageTag(),
                    ),
                    style: const TextStyle(
                      fontSize: 10,
                      color: MerzoxColors.kColor8D99AE,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (conversation.hasUnread)
                    Container(
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: MerzoxColors.kColorEE6C4D,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${conversation.unreadCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 18),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InboxAvatar extends StatelessWidget {
  final String url;
  final String label;

  const _InboxAvatar({required this.url, required this.label});

  @override
  Widget build(BuildContext context) {
    if (url.isNotEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundColor: MerzoxColors.kColorDEEEF8,
        backgroundImage: NetworkImage(url),
      );
    }

    return const CircleAvatar(
      radius: 24,
      backgroundColor: MerzoxColors.kColorDEEEF8,
      child: Icon(Icons.storefront_rounded, color: MerzoxColors.kColor3D5A80),
    );
  }
}

/// Today shows a clock, this week a weekday, anything older a short date —
/// the compact stamp the design puts at the end of each row.
String _formatTimestamp(DateTime? value, String localeName) {
  if (value == null) return '';

  final local = value.toLocal();
  final now = DateTime.now();
  final isToday =
      local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;

  if (isToday) {
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  if (now.difference(local).inDays < 7) {
    // Same rule as the tracking headline: an unnamed locale is English.
    return DateFormat.E(localeName).format(local);
  }

  return '${local.day}.${local.month}.${local.year}';
}
