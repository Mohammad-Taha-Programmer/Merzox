import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/core/constants/dates.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/core/localization/api_error_localizer.dart';

import '../bloc/chat_bloc.dart';
import '../bloc/chat_event.dart';
import '../bloc/chat_state.dart';
import '../highlighted_text.dart';
import '../widgets/match_navigator.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _composerController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  int _renderedMessageCount = 0;

  /// One key per occurrence the reader can be sent to.
  final Map<String, GlobalKey> _matchKeys = <String, GlobalKey>{};

  /// The occurrence already shown, so a rebuild does not scroll again under a
  /// reader who has since scrolled somewhere else themselves.
  String _shownMatch = '';

  GlobalKey _keyFor(String messageId) =>
      _matchKeys.putIfAbsent(messageId, GlobalKey.new);

  /// Brings an occurrence into view.
  ///
  /// A little above centre rather than at the very top: the lines before it
  /// are what make it readable, and a phrase pinned to the top edge arrives
  /// without the sentence it was part of.
  void _revealMatch(String messageId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? target = _matchKeys[messageId]?.currentContext;
      if (target == null) return;

      Scrollable.ensureVisible(
        target,
        alignment: 0.35,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _composerController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    final body = _composerController.text.trim();
    if (body.isEmpty) return;

    context.read<ChatBloc>().add(ChatMessageSent(body));
    _composerController.clear();
  }

  /// The thread is drawn oldest first, so any growth should land the viewer at
  /// the newest message rather than wherever the old offset happened to be.
  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: BlocConsumer<ChatBloc, ChatState>(
          listenWhen: (previous, current) =>
              previous.messages.length != current.messages.length ||
              previous.errorMessage != current.errorMessage ||
              previous.matchIndex != current.matchIndex ||
              previous.status != current.status,
          listener: (context, state) {
            final String match = state.currentMatchId;

            if (match.isNotEmpty && state.status == ChatStatus.ready) {
              // A reader who arrived from a result is taken to the place they
              // chose, not to the end of the thread.
              if (match != _shownMatch) {
                _shownMatch = match;
                _revealMatch(match);
              }
            } else if (state.messages.length > _renderedMessageCount) {
              _scrollToLatest();
            }

            _renderedMessageCount = state.messages.length;

            if (state.errorMessage.isNotEmpty) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(content: Text(_localizedError(state.errorMessage))),
                );
            }
          },
          builder: (context, state) {
            return Column(
              children: [
                _ChatHeader(title: state.title, avatarUrl: state.avatarUrl),
                const Divider(height: 1, color: MerzoxColors.kColorEFEFEF),
                if (state.readSyncFailed) const _ReadSyncNotice(),
                if (!state.anchorReached) const _MatchOutOfReachNotice(),
                Expanded(
                  child: Stack(
                    children: <Widget>[
                      _ChatBody(
                        state: state,
                        controller: _scrollController,
                        keyFor: _keyFor,
                      ),
                      if (state.matchIds.length > 1)
                        PositionedDirectional(
                          // The reading edge, where the artboard puts every
                          // control that belongs to the thread rather than to
                          // the app - the far corner is the bell's.
                          start: kMatchNavigatorInset,
                          bottom: kMatchNavigatorInset,
                          child: MatchNavigator(
                            current: state.matchIndex,
                            total: state.matchIds.length,
                            onNext: () => context.read<ChatBloc>().add(
                              const ChatMatchStepped(1),
                            ),
                            onPrevious: () => context.read<ChatBloc>().add(
                              const ChatMatchStepped(-1),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                _Composer(
                  controller: _composerController,
                  enabled: state.status != ChatStatus.sending,
                  onSend: _send,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  final String title;
  final String avatarUrl;

  const _ChatHeader({required this.title, required this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 66,
      child: Row(
        children: [
          const BackButton(color: MerzoxColors.kColor5E5E5E),
          _ChatAvatar(url: avatarUrl, label: title, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: MerzoxColors.kColor2B2B2B,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

/// A quiet strip, not a blocking error: the thread loaded and is usable, only
/// the read receipt failed to reach the server.
class _ReadSyncNotice extends StatelessWidget {
  const _ReadSyncNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: MerzoxColors.kColorF3EBB9.withValues(alpha: 0.45),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Row(
        children: [
          const Icon(
            Icons.sync_problem_rounded,
            size: 15,
            color: MerzoxColors.kColor767676,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'messages.readSyncFailed'.tr(),
              style: const TextStyle(
                fontSize: 10,
                color: MerzoxColors.kColor5E5E5E,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Says plainly that the place the reader tapped is further back than the
/// thread would page.
///
/// The alternative was to land somewhere near it and let them believe they had
/// arrived, which is worse than saying so.
class _MatchOutOfReachNotice extends StatelessWidget {
  const _MatchOutOfReachNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: MerzoxColors.kColorF3EBB9.withValues(alpha: 0.45),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.search_off_rounded,
            size: 15,
            color: MerzoxColors.kColor767676,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'messages.matchNotReached'.tr(),
              style: const TextStyle(
                fontSize: 10,
                color: MerzoxColors.kColor5E5E5E,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBody extends StatelessWidget {
  final ChatState state;
  final ScrollController controller;

  /// Hands each message the key that lets the page scroll to it.
  final GlobalKey Function(String messageId) keyFor;

  const _ChatBody({
    required this.state,
    required this.controller,
    required this.keyFor,
  });

  @override
  Widget build(BuildContext context) {
    if (state.status == ChatStatus.loading && state.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.status == ChatStatus.failure && state.messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 44,
                color: MerzoxColors.kColor8D99AE,
              ),
              const SizedBox(height: 12),
              Text(
                state.errorMessage.isEmpty
                    ? 'messages.loadError'.tr()
                    : _localizedError(state.errorMessage),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: MerzoxColors.kColor5E5E5E,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () =>
                    context.read<ChatBloc>().add(const ChatRefreshRequested()),
                child: Text('common.retry'.tr()),
              ),
            ],
          ),
        ),
      );
    }

    if (state.messages.isEmpty) {
      // `تفاصيل المتجر – 18` opens an empty thread with a banner rather than a
      // line of grey text: keep the conversation here, and here is who to tell
      // if something goes wrong. A thread that already has messages does not
      // draw it, and neither does this.
      return Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: MerzoxColors.kColorEEF6FB,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'messages.threadPrivacy'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: MerzoxColors.kColor3B3B3B,
                  fontSize: 12,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'messages.threadSupportHours'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: MerzoxColors.kColor8D99AE,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels <= 40 && state.hasMore) {
          context.read<ChatBloc>().add(const ChatOlderMessagesRequested());
        }
        return false;
      },
      child: ListView.builder(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        // While walking search results the whole thread is laid out, so an
        // occurrence far off screen has a context to be scrolled to. A list
        // that only builds what is visible cannot be told to reveal what is
        // not.
        scrollCacheExtent: state.isWalkingMatches
            ? const ScrollCacheExtent.pixels(kChatWalkCacheExtent)
            : null,
        itemCount: state.messages.length + (state.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (state.hasMore && index == 0) {
            return const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }

          final message = state.messages[state.hasMore ? index - 1 : index];
          return Column(
            key: state.matchIds.contains(message.id)
                ? keyFor(message.id)
                : null,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _MessageBubble(message: message, query: state.highlightQuery),
              _MessageStamp(at: message.createdAt, isMine: message.isMine),
            ],
          );
        },
      ),
    );
  }
}

/// How far beyond the viewport the thread is laid out while a reader is
/// stepping between search results. Large enough to cover the pages an anchor
/// can drag in, which is what makes an off-screen occurrence reachable.
const double kChatWalkCacheExtent = 20000;

class _MessageBubble extends StatelessWidget {
  final MessageApiModel message;

  /// What the reader searched for, marked wherever it appears. Empty when they
  /// arrived at the thread normally.
  final String query;

  const _MessageBubble({required this.message, this.query = ''});

  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine;

    // `الرسائل – 2` puts what you wrote at the START of the row in
    // #3D5A80 and what you were told at the end in #F9F9F9 — the sides a
    // reader of any direction expects, rather than mirroring with the
    // language. The tail is the corner that points back at whoever spoke.
    return Row(
      mainAxisAlignment: isMine
          ? MainAxisAlignment.start
          : MainAxisAlignment.end,
      children: [
        Flexible(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.72,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isMine
                  ? MerzoxColors.kColor3D5A80
                  : MerzoxColors.kColorF9F9F9,
              borderRadius: BorderRadiusDirectional.only(
                topStart: const Radius.circular(14),
                topEnd: const Radius.circular(14),
                bottomStart: Radius.circular(isMine ? 2 : 14),
                bottomEnd: Radius.circular(isMine ? 14 : 2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  highlightedSpan(
                    text: message.body,
                    query: query,
                    style: TextStyle(
                      color: isMine ? Colors.white : MerzoxColors.kColor3B3B3B,
                      fontSize: 12,
                      height: 1.5,
                    ),
                    // A wash that reads on both bubbles, with the darker
                    // text over it: the same mark whichever side spoke.
                    background: MerzoxColors.kColorF2CB06,
                    foreground: MerzoxColors.kColor2B2B2B,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// When a message arrived, under the bubble it belongs to.
///
/// It used to sit inside the bubble at 9pt, in white-on-blue for your own
/// messages, and carried the clock with no day - so a thread read weeks later
/// said 9:43 without saying 9:43 of when. Outside the bubble it can be the
/// same colour on both sides and large enough to actually read, and the day
/// travels with the clock.
class _MessageStamp extends StatelessWidget {
  final DateTime? at;

  /// Which side the bubble above it is on, so the stamp sits under its own
  /// corner rather than floating between two messages.
  final bool isMine;

  const _MessageStamp({required this.at, required this.isMine});

  @override
  Widget build(BuildContext context) {
    if (at == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 6, end: 6, top: 3),
      child: Row(
        mainAxisAlignment: isMine
            ? MainAxisAlignment.start
            : MainAxisAlignment.end,
        children: <Widget>[
          Text(
            merzoxMessageStamp(at),
            // Laid out left to right whatever the language around it. Both
            // halves are digits, and in an Arabic paragraph the runs reorder:
            // the day ends up after the clock, which reads as a different
            // stamp rather than as the same one written differently.
            textDirection: TextDirection.ltr,
            style: const TextStyle(
              fontSize: kChatStampSize,
              color: MerzoxColors.kColor8D99AE,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small, but not too small to read: the size the row above it uses for its
/// own last line, one step down.
const double kChatStampSize = 11;

/// The day and the clock of one message, in that order.
///
/// The day is the app's one calendar format; putting it first keeps a column
/// of stamps aligned on the part that changes least.
String merzoxMessageStamp(DateTime? value) {
  if (value == null) return '';

  return '${merzoxDay(value)} - ${_formatTime(value)}';
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: 12 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: MerzoxColors.kColorF9F9F9,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: MerzoxColors.kColorEFEFEF),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 4,
                maxLength: 2000,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  counterText: '',
                  border: InputBorder.none,
                  hintText: 'messages.composerHint'.tr(),
                  hintStyle: const TextStyle(
                    color: MerzoxColors.kColor9F9F9F,
                    fontSize: 12,
                  ),
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: MerzoxColors.kColorEE6C4D,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled ? onSend : null,
              child: SizedBox(
                width: 46,
                height: 46,
                child: enabled
                    ? const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 20,
                      )
                    : const Padding(
                        padding: EdgeInsets.all(14),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatAvatar extends StatelessWidget {
  final String url;
  final String label;
  final double size;

  const _ChatAvatar({
    required this.url,
    required this.label,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final initial = label.trim().isEmpty ? '?' : label.trim().characters.first;

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: MerzoxColors.kColorDEEEF8,
        shape: BoxShape.circle,
      ),
      child: url.isEmpty
          ? Center(
              child: Text(
                initial,
                style: TextStyle(
                  color: MerzoxColors.kColor3D5A80,
                  fontSize: size * 0.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Center(
                child: Text(
                  initial,
                  style: TextStyle(
                    color: MerzoxColors.kColor3D5A80,
                    fontSize: size * 0.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
    );
  }
}

String _localizedError(String message) {
  if (message.startsWith('messages.')) return message.tr();
  return localizeApiErrorOrRaw(message);
}

String _formatTime(DateTime? value) {
  if (value == null) return '';
  final local = value.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final suffix = local.hour >= 12 ? 'PM' : 'AM';

  return '$hour:$minute $suffix';
}
