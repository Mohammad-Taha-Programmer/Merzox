import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';

import '../../../core/constants/colors.dart';
import '../../../core/localization/api_error_localizer.dart';
import '../../../core/widgets/remote_circle_avatar.dart';
import '../../../services/api_service.dart';
import '../bloc/messages_search_state.dart';
import '../highlighted_text.dart';

/// What a typed query found, in the two shapes it can be found in.
///
/// A name and a phrase are answered separately and shown separately. Merging
/// them into one ranked list would force the reader to work out, per row, why
/// it is there - and a thread that matches by name behaves differently when
/// tapped from one that matches by something said inside it.
class MessagesSearchResults extends StatelessWidget {
  final MessagesSearchState state;

  /// Open the thread at its newest message, as tapping the inbox does.
  final void Function(ConversationApiModel conversation) onOpenThread;

  /// Open the thread at the first place the phrase was said.
  final void Function(ConversationMessageMatchApiModel match) onOpenMatch;

  final EdgeInsets padding;

  const MessagesSearchResults({
    required this.state,
    required this.onOpenThread,
    required this.onOpenMatch,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 24),
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (state.foundNothing) {
      return _Empty(query: state.query.trim());
    }

    return ListView(
      padding: padding,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: <Widget>[
        if (state.status == MessagesSearchStatus.failure &&
            state.errorMessage.isNotEmpty)
          _Trouble(message: state.errorMessage),
        if (state.people.isNotEmpty) ...<Widget>[
          _SectionLabel(label: 'messages.searchPeople'.tr()),
          for (final ConversationApiModel conversation in state.people)
            _PersonRow(
              conversation: conversation,
              query: state.answeredQuery,
              onTap: () => onOpenThread(conversation),
            ),
        ],
        if (state.messages.isNotEmpty) ...<Widget>[
          _SectionLabel(label: 'messages.searchInMessages'.tr()),
          for (final ConversationMessageMatchApiModel match in state.messages)
            _MatchRow(
              match: match,
              query: state.answeredQuery,
              onTap: () => onOpenMatch(match),
            ),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: MerzoxColors.kColor8D99AE,
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  final ConversationApiModel conversation;
  final String query;
  final VoidCallback onTap;

  const _PersonRow({
    required this.conversation,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _ResultShell(
      onTap: onTap,
      avatarUrl: conversation.avatarUrl,
      title: Text.rich(
        highlightedSpan(
          text: conversation.title,
          query: query,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: MerzoxColors.kColor3B3B3B,
          ),
          background: MerzoxColors.kColorDEEEF8,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        conversation.lastMessage.body.isEmpty
            ? 'messages.noMessagesYet'.tr()
            : conversation.lastMessage.body,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: MerzoxColors.kColor9F9F9F),
      ),
      trailing: null,
    );
  }
}

class _MatchRow extends StatelessWidget {
  final ConversationMessageMatchApiModel match;
  final String query;
  final VoidCallback onTap;

  const _MatchRow({
    required this.match,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _ResultShell(
      onTap: onTap,
      avatarUrl: match.conversation.avatarUrl,
      title: Text(
        match.conversation.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: MerzoxColors.kColor3B3B3B,
        ),
      ),
      subtitle: Text.rich(
        highlightedSpan(
          text: match.snippet,
          query: query,
          style: const TextStyle(
            fontSize: 12,
            color: MerzoxColors.kColor5E5E5E,
          ),
          background: MerzoxColors.kColorDEEEF8,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      // How many times it was said, so the reader knows before tapping that
      // there is more than one place to stand.
      trailing: match.matchCount > 1
          ? Container(
              key: const ValueKey<String>('merzox.messages.matchCount'),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: MerzoxColors.kColorDEEEF8,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                '${match.matchCount}',
                style: const TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: MerzoxColors.kColor3D5A80,
                ),
              ),
            )
          : null,
    );
  }
}

class _ResultShell extends StatelessWidget {
  final VoidCallback onTap;
  final String avatarUrl;
  final Widget title;
  final Widget subtitle;
  final Widget? trailing;

  const _ResultShell({
    required this.onTap,
    required this.avatarUrl,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: <Widget>[
              RemoteCircleAvatar(
                url: avatarUrl,
                radius: 20,
                backgroundColor: MerzoxColors.kColorDEEEF8,
                fallback: const Icon(
                  Icons.storefront_rounded,
                  size: 20,
                  color: MerzoxColors.kColor3D5A80,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    title,
                    const SizedBox(height: 3),
                    subtitle,
                  ],
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: 10),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Trouble extends StatelessWidget {
  final String message;

  const _Trouble({required this.message});

  @override
  Widget build(BuildContext context) {
    // A strip, not a blank screen: whatever was found before the connection
    // faltered is still on the list below and is still true.
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: MerzoxColors.kColorF3EBB9.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        localizeApiErrorOrRaw(message),
        style: const TextStyle(fontSize: 12, color: MerzoxColors.kColor5E5E5E),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String query;

  const _Empty({required this.query});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.search_off_rounded,
              size: 44,
              color: MerzoxColors.kColorBEBEBE,
            ),
            const SizedBox(height: 12),
            Text(
              'messages.searchNoResults'.tr(
                namedArgs: <String, String>{'query': query},
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.6,
                color: MerzoxColors.kColor767676,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
