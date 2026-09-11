import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/core/constants/dates.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/core/localization/api_error_localizer.dart';

import 'package:merzox/features/notifications/widgets/global_notification_bell.dart';

import '../bloc/chat_bloc.dart';
import '../bloc/chat_event.dart';
import '../bloc/chat_state.dart';
import '../highlighted_text.dart';
import '../widgets/shared_product_card.dart';
import 'share_product_page.dart';
import '../widgets/match_navigator.dart';

/// Asks the reader to pick one of this conversation's products.
///
/// Returns what they chose, or null if they came back empty-handed.
typedef ChatProductPicker =
    Future<BusinessProductApiModel?> Function(
      BuildContext context,
      String conversationId,
    );

/// Opens the shelves this conversation may share from.
///
/// The conversation's id is the only thing handed over: which shop those
/// shelves belong to is the server's answer, which is what keeps either side
/// from reaching into a catalogue that is not part of this conversation.
Future<BusinessProductApiModel?> openChatProductPicker(
  BuildContext context,
  String conversationId,
) {
  return Navigator.of(context).push<BusinessProductApiModel>(
    MaterialPageRoute<BusinessProductApiModel>(
      builder: (_) => ShareProductPage(conversationId: conversationId),
    ),
  );
}

class ChatPage extends StatefulWidget {
  /// How a product is chosen. The default opens the picker screen; a test
  /// hands one over without standing up a server.
  final ChatProductPicker? productPicker;

  const ChatPage({super.key, this.productPicker});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _composerController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  int _renderedMessageCount = 0;

  /// Chosen from the shop's shelves and waiting under the message box.
  ///
  /// It sits here rather than being sent on the spot so the sender can say
  /// something about it first - which is usually why they are sharing it.
  BusinessProductApiModel? _pendingProduct;

  /// The message being answered, shown as a quote over the box.
  ///
  /// An answer may be words, a product, or both - the quote is what makes it
  /// an answer, and it is dropped once it is sent.
  MessageApiModel? _pendingReply;

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
    final BusinessProductApiModel? product = _pendingProduct;
    final MessageApiModel? answered = _pendingReply;

    // A card on its own is a message; only both being absent is nothing. A
    // quote is not content of its own - answering with nothing said is not a
    // message.
    if (body.isEmpty && product == null) return;

    context.read<ChatBloc>().add(
      ChatMessageSent(body, productId: product?.id, replyToId: answered?.id),
    );
    _composerController.clear();

    if (product != null || answered != null) {
      setState(() {
        _pendingProduct = null;
        _pendingReply = null;
      });
    }
  }

  /// Asks why, then sends it.
  ///
  /// A reason is required and comes from a fixed list, because a report is
  /// read by a person afterwards and one that said only that somebody
  /// complained could not be acted on. The words beside it are optional and
  /// are where a reader says what the list does not cover.
  Future<void> _openReport() async {
    final _ReportDraft? draft = await showModalBottomSheet<_ReportDraft>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => const _ReportSheet(),
    );

    if (draft == null || !mounted) return;

    context.read<ChatBloc>().add(
      ChatReportSubmitted(reason: draft.reason, note: draft.note),
    );
  }

  /// Offers what can be done with one message.
  ///
  /// A long press rather than a tap: a tap on a shared card opens the
  /// product, and the two must not fight over the same touch.
  Future<void> _openMessageActions(MessageApiModel message) async {
    final _MessageAction? action = await showModalBottomSheet<_MessageAction>(
      context: context,
      builder: (BuildContext sheetContext) =>
          _MessageActionsSheet(message: message),
    );

    if (action == null || !mounted) return;

    switch (action) {
      case _MessageAction.reply:
        setState(() => _pendingReply = message);

      case _MessageAction.copy:
        await Clipboard.setData(ClipboardData(text: _copyableText(message)));
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('messages.actionCopied'.tr())));

      case _MessageAction.bookmark:
        context.read<ChatBloc>().add(ChatMessageBookmarkToggled(message.id));
    }
  }

  /// What copying a message puts on the clipboard.
  ///
  /// A shared card has no words of its own, so the product's name stands in -
  /// copying it and getting an empty clipboard would read as a fault.
  String _copyableText(MessageApiModel message) {
    final String body = message.body.trim();
    if (body.isNotEmpty) return body;

    return message.sharedProduct?.name ?? '';
  }

  Future<void> _pickProduct() async {
    final String conversationId = context.read<ChatBloc>().state.conversationId;
    if (conversationId.isEmpty) return;

    final BusinessProductApiModel? picked =
        await (widget.productPicker ?? openChatProductPicker)(
          context,
          conversationId,
        );

    if (picked == null || !mounted) return;

    setState(() => _pendingProduct = picked);
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
              previous.noticeCode != current.noticeCode ||
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

            if (state.noticeCode.isNotEmpty) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(state.noticeCode.tr())));
            }

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
                _ChatHeader(
                  title: state.title,
                  avatarUrl: state.avatarUrl,
                  blockedByMe: state.blockedByMe,
                  onToggleBlock: () =>
                      context.read<ChatBloc>().add(const ChatBlockToggled()),
                  onReport: _openReport,
                ),
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
                        onMessageActions: _openMessageActions,
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
                // The box is replaced rather than disabled: one that took
                // words nothing would carry is worse than its absence.
                if (state.isBlocked)
                  _BlockedNotice(
                    blockedByMe: state.blockedByMe,
                    onUnblock: () =>
                        context.read<ChatBloc>().add(const ChatBlockToggled()),
                  )
                else
                  _Composer(
                    controller: _composerController,
                    enabled: state.status != ChatStatus.sending,
                    onSend: _send,
                    onShareProduct: _pickProduct,
                    pendingProduct: _pendingProduct,
                    onDropPendingProduct: () =>
                        setState(() => _pendingProduct = null),
                    pendingReply: _pendingReply,
                    onDropPendingReply: () =>
                        setState(() => _pendingReply = null),
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

  /// Whether this reader has closed the door, which decides what the menu
  /// offers rather than whether it appears.
  final bool blockedByMe;

  /// Closes the door, or opens it again.
  final VoidCallback onToggleBlock;

  /// Tells the operator about the other side.
  final VoidCallback onReport;

  const _ChatHeader({
    required this.title,
    required this.avatarUrl,
    required this.blockedByMe,
    required this.onToggleBlock,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 66,
      child: Row(
        children: [
          // A chevron rather than Material's full arrow, which is what the
          // board draws. Named for what it does and left for Material to
          // turn: `chevron_left` carries `matchTextDirection`, so it leans
          // right in Arabic and left in English on its own.
          IconButton(
            key: const ValueKey<String>('chat.back'),
            tooltip: 'common.back'.tr(),
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(
              Icons.chevron_left_rounded,
              color: MerzoxColors.kColor5E5E5E,
              size: 28,
            ),
          ),
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
          const SizedBox(width: 4),
          // At the far end of the bar, where what belongs to the thread as a
          // whole lives rather than to any one message in it.
          IconButton(
            key: const ValueKey<String>('chat.threadMenu'),
            tooltip: 'messages.inboxMenuTooltip'.tr(),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (BuildContext sheetContext) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const SizedBox(height: 8),
                    ListTile(
                      key: const ValueKey<String>('chat.toggleBlock'),
                      leading: Icon(
                        blockedByMe
                            ? Icons.lock_open_rounded
                            : Icons.block_rounded,
                        color: blockedByMe
                            ? MerzoxColors.kColor3D5A80
                            : MerzoxColors.kColorE40909,
                      ),
                      title: Text(
                        blockedByMe
                            ? 'messages.unblockUser'.tr()
                            : 'messages.blockUser'.tr(),
                      ),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        onToggleBlock();
                      },
                    ),
                    ListTile(
                      key: const ValueKey<String>('chat.report'),
                      leading: const Icon(
                        Icons.flag_outlined,
                        color: MerzoxColors.kColorEE6C4D,
                      ),
                      title: Text('messages.reportUser'.tr()),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        onReport();
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
              color: MerzoxColors.kColor5E5E5E,
            ),
          ),
          // Past the whole of the floating bell - its inset from the edge
          // plus the width it takes. The bell is drawn above the router, so
          // anything left in this corner is not merely half covered but
          // unclickable: its taps go to the bell. The same room every other
          // bar in the app leaves it.
          const SizedBox(width: kGlobalBellInset + kGlobalBellReservedWidth),
        ],
      ),
    );
  }
}

/// Why nothing can be written here.
///
/// It stands where the message box was, because the box is gone: a field that
/// took words nothing would carry is worse than its absence. The two cases
/// are told apart - one of them the reader can undo from here, and the other
/// is not theirs to undo.
class _BlockedNotice extends StatelessWidget {
  final bool blockedByMe;
  final VoidCallback onUnblock;

  const _BlockedNotice({required this.blockedByMe, required this.onUnblock});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey<String>('chat.blockedNotice'),
      width: double.infinity,
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 14,
        bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      color: MerzoxColors.kColorF9F9F9,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            blockedByMe
                ? 'messages.blockedByMeNotice'.tr()
                : 'messages.blockedMeNotice'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              height: 1.6,
              color: MerzoxColors.kColor8D99AE,
            ),
          ),
          if (blockedByMe) ...<Widget>[
            const SizedBox(height: 10),
            OutlinedButton(
              key: const ValueKey<String>('chat.unblockFromNotice'),
              onPressed: onUnblock,
              child: Text('messages.unblockUser'.tr()),
            ),
          ],
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

  /// Opens what can be done with one message.
  final void Function(MessageApiModel message) onMessageActions;

  const _ChatBody({
    required this.onMessageActions,
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
              _MessageBubble(
                message: message,
                query: state.highlightQuery,
                onLongPress: () => onMessageActions(message),
              ),
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

  /// Opens what can be done with this message. Null in a context where
  /// nothing can be - the marked list, which only shows them.
  final VoidCallback? onLongPress;

  /// What the reader searched for, marked wherever it appears. Empty when they
  /// arrived at the thread normally.
  final String query;

  const _MessageBubble({
    required this.message,
    this.query = '',
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine;
    final SharedProductApiModel? shared = message.sharedProduct;

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
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: onLongPress,
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
                  if (message.replyTo != null) ...<Widget>[
                    _QuotedMessage(reply: message.replyTo!, onDark: isMine),
                    const SizedBox(height: 8),
                  ],
                  if (shared != null) ...<Widget>[
                    SharedProductCard.shared(
                      product: shared,
                      onTap: () => openSharedProduct(context, shared),
                    ),
                    // Only when there are words to separate from it. A card sent
                    // on its own is the whole message.
                    if (message.body.trim().isNotEmpty)
                      const SizedBox(height: 8),
                  ],
                  if (message.body.trim().isNotEmpty)
                    Text.rich(
                      highlightedSpan(
                        text: message.body,
                        query: query,
                        style: TextStyle(
                          color: isMine
                              ? Colors.white
                              : MerzoxColors.kColor3B3B3B,
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
  final VoidCallback onShareProduct;

  /// Chosen but not yet sent, shown above the box so the sender can see what
  /// is going with their words - and take it back off.
  final BusinessProductApiModel? pendingProduct;
  final VoidCallback onDropPendingProduct;

  /// The message being answered, quoted over the box.
  final MessageApiModel? pendingReply;
  final VoidCallback onDropPendingReply;

  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onSend,
    required this.onShareProduct,
    required this.onDropPendingProduct,
    required this.onDropPendingReply,
    this.pendingProduct,
    this.pendingReply,
  });

  @override
  Widget build(BuildContext context) {
    final BusinessProductApiModel? pending = pendingProduct;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: 12 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (pendingReply != null)
            _PendingReply(message: pendingReply!, onRemove: onDropPendingReply),
          if (pending != null)
            _PendingProduct(product: pending, onRemove: onDropPendingProduct),
          Row(
            children: <Widget>[
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
              // Beside the send button, and built like it: the same circle at
              // the same size, in the board's light blue rather than its
              // orange. The two things a reader does when they have finished
              // composing, told apart by colour instead of by size - it was a
              // bare glyph half the send button's weight, which read as a
              // decoration next to it.
              Material(
                color: MerzoxColors.kColor98C1D9,
                shape: const CircleBorder(),
                child: InkWell(
                  key: const ValueKey<String>('chat.shareProduct'),
                  customBorder: const CircleBorder(),
                  onTap: enabled ? onShareProduct : null,
                  child: Tooltip(
                    message: 'messages.shareProductTooltip'.tr(),
                    child: const SizedBox(
                      width: kChatComposerButton,
                      height: kChatComposerButton,
                      child: Icon(
                        Icons.local_offer_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
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
                    width: kChatComposerButton,
                    height: kChatComposerButton,
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
        ],
      ),
    );
  }
}

/// What can be done with one message.
enum _MessageAction { reply, copy, bookmark }

/// The sheet a long press opens.
class _MessageActionsSheet extends StatelessWidget {
  final MessageApiModel message;

  const _MessageActionsSheet({required this.message});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(height: 8),
          ListTile(
            key: const ValueKey<String>('chat.actionReply'),
            leading: const Icon(Icons.reply_rounded),
            title: Text('messages.actionReply'.tr()),
            onTap: () => Navigator.of(context).pop(_MessageAction.reply),
          ),
          ListTile(
            key: const ValueKey<String>('chat.actionCopy'),
            leading: const Icon(Icons.copy_rounded),
            title: Text('messages.actionCopy'.tr()),
            onTap: () => Navigator.of(context).pop(_MessageAction.copy),
          ),
          ListTile(
            key: const ValueKey<String>('chat.actionBookmark'),
            leading: Icon(
              message.bookmarked
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
            ),
            // The same entry either way round: it is one mark, and a reader
            // who marked something by mistake looks for it where they put it.
            title: Text(
              message.bookmarked
                  ? 'messages.actionUnbookmark'.tr()
                  : 'messages.actionBookmark'.tr(),
            ),
            onTap: () => Navigator.of(context).pop(_MessageAction.bookmark),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// The message an answer answers, drawn inside the answer.
///
/// A bar down the reading edge and the words beside it, dimmed - the shape a
/// quote has everywhere, so it reads as "about this" rather than as part of
/// what was said.
class _QuotedMessage extends StatelessWidget {
  final MessageReplyApiModel reply;

  /// True inside one's own bubble, which is dark: the same quote has to be
  /// legible on both.
  final bool onDark;

  const _QuotedMessage({required this.reply, required this.onDark});

  @override
  Widget build(BuildContext context) {
    final Color ink = onDark ? Colors.white : MerzoxColors.kColor3B3B3B;

    return Container(
      key: const ValueKey<String>('chat.quotedMessage'),
      padding: const EdgeInsetsDirectional.only(start: 8, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: (onDark ? Colors.white : MerzoxColors.kColor8D99AE).withValues(
          alpha: onDark ? 0.14 : 0.10,
        ),
        borderRadius: BorderRadius.circular(6),
        border: BorderDirectional(
          start: BorderSide(
            color: onDark ? Colors.white : MerzoxColors.kColor98C1D9,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            reply.senderName.trim().isEmpty
                ? 'messages.quotedFallbackName'.tr()
                : reply.senderName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: ink.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            quotedMessagePreview(reply),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: ink.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}

/// What a quote shows of the message it quotes.
///
/// A shared card has no words of its own, so the quote says what it was.
/// Showing an empty line there would read as a fault rather than as a card.
String quotedMessagePreview(MessageReplyApiModel reply) {
  final String body = reply.body.trim();
  if (body.isNotEmpty) return body;

  return reply.hasProduct
      ? 'messages.quotedProduct'.tr()
      : 'messages.quotedEmpty'.tr();
}

/// The message being answered, over the box the answer is written in.
class _PendingReply extends StatelessWidget {
  final MessageApiModel message;
  final VoidCallback onRemove;

  const _PendingReply({required this.message, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final String preview = message.body.trim().isNotEmpty
        ? message.body.trim()
        : (message.sharedProduct != null
              ? 'messages.quotedProduct'.tr()
              : 'messages.quotedEmpty'.tr());

    return Container(
      key: const ValueKey<String>('chat.pendingReply'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsetsDirectional.only(start: 10, top: 6, bottom: 6),
      decoration: BoxDecoration(
        color: MerzoxColors.kColorF9F9F9,
        borderRadius: BorderRadius.circular(8),
        border: const BorderDirectional(
          start: BorderSide(color: MerzoxColors.kColor98C1D9, width: 3),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'messages.replyingTo'.tr(
                    args: <String>[
                      message.senderName.trim().isEmpty
                          ? 'messages.quotedFallbackName'.tr()
                          : message.senderName,
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: MerzoxColors.kColor8D99AE,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: MerzoxColors.kColor3B3B3B,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey<String>('chat.dropPendingReply'),
            tooltip: 'common.cancel'.tr(),
            onPressed: onRemove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: MerzoxColors.kColor8D99AE,
            ),
          ),
        ],
      ),
    );
  }
}

/// What a reader chose to say about somebody.
class _ReportDraft {
  final String reason;
  final String note;

  const _ReportDraft({required this.reason, required this.note});
}

/// Asks why, before anything is sent.
///
/// The reasons are the server's own list; one this screen offered but the
/// server refused would be a form that fails on send, so a test holds the two
/// together.
class _ReportSheet extends StatefulWidget {
  const _ReportSheet();

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final TextEditingController _note = TextEditingController();

  /// Nothing is chosen to begin with: a reason picked by default is a reason
  /// nobody chose, and the pile it lands in is the one nobody can trust.
  String? _reason;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'messages.reportTitle'.tr(),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: MerzoxColors.kColor2B2B2B,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'messages.reportSubtitle'.tr(),
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: MerzoxColors.kColor8D99AE,
                ),
              ),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: _reason,
                onChanged: (String? value) => setState(() => _reason = value),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (final String reason in merzoxReportReasons)
                      RadioListTile<String>(
                        key: ValueKey<String>('chat.reportReason.$reason'),
                        value: reason,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(
                          'messages.reportReasons.$reason'.tr(),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              TextField(
                key: const ValueKey<String>('chat.reportNote'),
                controller: _note,
                minLines: 2,
                maxLines: 4,
                maxLength: kReportNoteMax,
                decoration: InputDecoration(
                  hintText: 'messages.reportNoteHint'.tr(),
                  hintStyle: const TextStyle(
                    color: MerzoxColors.kColor9F9F9F,
                    fontSize: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey<String>('chat.reportSend'),
                  // Nothing to send until a reason is chosen, and a button
                  // that looked ready would only fail at the server.
                  onPressed: _reason == null
                      ? null
                      : () => Navigator.of(
                          context,
                        ).pop(_ReportDraft(reason: _reason!, note: _note.text)),
                  style: FilledButton.styleFrom(
                    backgroundColor: MerzoxColors.kColorEE6C4D,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: Text('messages.reportSend'.tr()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The round buttons at the end of the composer row.
///
/// One size for both: sending, and reaching for something to send.
const double kChatComposerButton = 46;

/// How tall the picture is on the card being written.
///
/// Shorter than the one in the thread: this sits above the keyboard, and a
/// full-height card there would push the words being typed off the screen.
const double kPendingProductImageHeight = 76;

/// The product chosen but not yet sent, above the box the words go in.
///
/// The card and nothing else. It was wrapped in a rounded grey panel with a
/// label beside it, which is the shape of the message field - so the empty
/// half of that panel read as a second box that would not take any typing.
/// The card carries its own dismiss badge instead, and the only thing on this
/// screen shaped like a text field is the text field.
class _PendingProduct extends StatelessWidget {
  final BusinessProductApiModel product;
  final VoidCallback onRemove;

  const _PendingProduct({required this.product, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey<String>('chat.pendingProduct'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            SharedProductCard(
              name: product.name,
              price: product.displayPrice,
              imageUrl: product.imageUrl,
              imageHeight: kPendingProductImageHeight,
            ),
            PositionedDirectional(
              top: -6,
              end: -6,
              child: Material(
                color: Colors.white,
                shape: const CircleBorder(),
                elevation: 1,
                shadowColor: Colors.black26,
                child: InkWell(
                  key: const ValueKey<String>('chat.dropPendingProduct'),
                  customBorder: const CircleBorder(),
                  onTap: onRemove,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: MerzoxColors.kColor8D99AE,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
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
