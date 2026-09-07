import 'package:merzox/core/widgets/remote_circle_avatar.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:merzox/core/constants/dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/core/localization/api_error_localizer.dart';

import '../bloc/messages_bloc.dart';
import '../bloc/messages_event.dart';
import '../bloc/messages_search_bloc.dart';
import '../bloc/messages_search_state.dart';
import '../bloc/messages_state.dart';
import 'bookmarks_page.dart';
import '../widgets/messages_header.dart';
import '../widgets/messages_search_results.dart';

/// The inbox from the design: an "all / unread" pair of tabs over a list of
/// threads. It is shared by the customer tab and the merchant shell, which
/// differ only in the bloc they are given.
class MessagesInboxView extends StatefulWidget {
  final String title;
  final EdgeInsets padding;
  final bool showTitle;

  /// Whether the header offers a way back. The merchant reaches the inbox from
  /// their profile; the customer's is a tab and has nowhere to return to.
  final bool showBack;

  const MessagesInboxView({
    super.key,
    required this.title,
    this.padding = const EdgeInsets.fromLTRB(16, 18, 16, 118),
    this.showTitle = true,
    this.showBack = false,
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

  /// Opens the thread at the first place a searched-for phrase was said.
  ///
  /// The whole match list travels with it, so the chat can offer the reader
  /// the other places without asking the server the same question twice.
  Future<void> _openMatch(ConversationMessageMatchApiModel match) async {
    final MessagesSearchBloc search = context.read<MessagesSearchBloc>();
    final MessagesBloc bloc = context.read<MessagesBloc>();

    await context.push(
      Uri(
        path: '/chat',
        queryParameters: <String, String>{
          'conversationId': match.conversation.id,
          'title': match.conversation.title,
          'avatarUrl': match.conversation.avatarUrl,
          'q': search.state.answeredQuery,
          'matches': match.matchIds.join(','),
        },
      ).toString(),
    );

    if (!mounted) return;
    bloc.add(const MessagesRefreshRequested());
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MessagesSearchBloc, MessagesSearchState>(
      builder: (BuildContext context, MessagesSearchState search) {
        return Column(
          children: <Widget>[
            if (widget.showTitle)
              MessagesHeader(title: widget.title, showBack: widget.showBack),
            Expanded(
              child: search.showsResults
                  ? MessagesSearchResults(
                      state: search,
                      padding: widget.padding.copyWith(top: 0),
                      onOpenThread: _openThread,
                      onOpenMatch: _openMatch,
                    )
                  : _list(context),
            ),
          ],
        );
      },
    );
  }

  Widget _list(BuildContext context) {
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
              _InboxTabs(
                filter: state.filter,
                unreadCount: state.unreadConversationCount,
              ),
              // The artboard opens its first row at 179, under a 44-tall tab
              // band that starts at 112.
              const SizedBox(height: 41),
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

/// What separates the dots from `الكل`.
///
/// Enough that a thumb aimed at one does not land on the other, and no more:
/// they are one group at the reading edge, and the width of the screen
/// belongs between the two filters rather than inside this pair.
const double kInboxMenuGap = 8;

class _InboxTabs extends StatelessWidget {
  final MessagesFilter filter;
  final int unreadCount;

  const _InboxTabs({required this.filter, required this.unreadCount});

  @override
  Widget build(BuildContext context) {
    // The artboard puts `الكل` at the reading edge and `غير مقروءة` at the far
    // one, with the whole width between them rather than a fixed gap.
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // The dots and `الكل` travel together at the reading edge, with only
        // a thumb's width between them. Left as three children of a
        // space-between row they split the leftover width into two gaps, and
        // the one between these two was as wide as the one that is meant to
        // be - the whole point of which is to push the two filters apart.
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // What hangs off the dots belongs to the reader rather than to
            // any one thread - what they marked, and later what they blocked
            // or reported.
            const _InboxMenuButton(),
            const SizedBox(width: kInboxMenuGap),
            _InboxTab(
              label: 'messages.tabAll'.tr(),
              badge: 0,
              selected: filter == MessagesFilter.all,
              onTap: () => context.read<MessagesBloc>().add(
                const MessagesFilterChanged(MessagesFilter.all),
              ),
            ),
          ],
        ),
        _InboxTab(
          label: 'messages.tabUnread'.tr(),
          badge: unreadCount,
          selected: filter == MessagesFilter.unread,
          onTap: () => context.read<MessagesBloc>().add(
            const MessagesFilterChanged(MessagesFilter.unread),
          ),
        ),
      ],
    );
  }
}

/// The three dots beside the filters.
///
/// One entry today - the marked messages - and it is deliberately the only
/// one: blocking and reporting are named in the same breath but are not
/// built, and a menu entry that did nothing would be worse than its absence.
class _InboxMenuButton extends StatelessWidget {
  const _InboxMenuButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const ValueKey<String>('messages.inboxMenu'),
      tooltip: 'messages.inboxMenuTooltip'.tr(),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        builder: (BuildContext sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(height: 8),
              ListTile(
                key: const ValueKey<String>('messages.openBookmarks'),
                leading: const Icon(Icons.bookmark_border_rounded),
                title: Text('messages.bookmarksTitle'.tr()),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const BookmarksPage(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      icon: const Icon(
        Icons.more_vert_rounded,
        size: 20,
        color: MerzoxColors.kColor3D5A80,
      ),
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

/// The moment a row's stamp is about.
///
/// The last message RECEIVED, not the last message. The two differ every time
/// you answer someone: the thread rises to the top and the stamp would jump to
/// your own reply, so a row would tell you when you last spoke rather than how
/// long they have been waiting.
///
/// Before anyone has written back there is no such moment, and the row falls
/// back to the thread's own last message rather than showing a gap where a
/// time belongs - the only case where the two can disagree and the honest
/// answer is nothing at all.
DateTime? conversationStamp(ConversationApiModel conversation) =>
    conversation.lastReceivedAt ?? conversation.lastMessage.sentAt;

/// The row's type sizes.
///
/// The artboard sets the name at 13 and the last line at 10, which measured
/// fine on a 375-wide board and reads small on a phone held at arm's length.
/// These are that scale raised by the two steps a body face needs before it is
/// comfortable, keeping the difference between the three intact.
const double kInboxNameSize = 15;
const double kInboxPreviewSize = 12;
const double kInboxStampSize = 12;

/// How far the stamp drops to sit on the name's baseline.
const double kInboxStampNudge = 3;

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
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          // An unread row carries the tint; the rest of the band is the page.
          // The artboard draws no card, no border and no gap between rows.
          color: conversation.hasUnread
              ? MerzoxColors.kColorEEF6FB
              : Colors.white,
          child: Row(
            children: [
              _InboxAvatar(
                url: conversation.avatarUrl,
                label: conversation.title,
              ),
              const SizedBox(width: 12),
              // The two text columns are top-aligned to each other while the
              // avatar stays centred on the row: the artboard sets the stamp
              // on the name's line, not halfway down the card.
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            conversation.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: kInboxNameSize,
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
                            // The artboard wraps a long last message onto a
                            // second line rather than cutting it at the first.
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: kInboxPreviewSize,
                              color: conversation.hasUnread
                                  ? MerzoxColors.kColor3B3B3B
                                  : MerzoxColors.kColor767676,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Padding(
                      // A smaller face sits higher in its line box; this drops
                      // the stamp back onto the name's baseline.
                      padding: const EdgeInsets.only(top: kInboxStampNudge),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _formatTimestamp(
                              conversationStamp(conversation),
                              context.locale.toLanguageTag(),
                            ),
                            style: const TextStyle(
                              fontSize: kInboxStampSize,
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
                    ),
                  ],
                ),
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
    return RemoteCircleAvatar(
      url: url,
      radius: 24,
      backgroundColor: MerzoxColors.kColorDEEEF8,
      fallback: const Icon(
        Icons.storefront_rounded,
        color: MerzoxColors.kColor3D5A80,
      ),
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

  return merzoxDay(local);
}
