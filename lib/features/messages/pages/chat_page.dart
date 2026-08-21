import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/services/api_service.dart';

import '../bloc/chat_bloc.dart';
import '../bloc/chat_event.dart';
import '../bloc/chat_state.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _composerController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  int _renderedMessageCount = 0;

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
              previous.errorMessage != current.errorMessage,
          listener: (context, state) {
            if (state.messages.length > _renderedMessageCount) {
              _scrollToLatest();
            }
            _renderedMessageCount = state.messages.length;

            if (state.errorMessage.isNotEmpty) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(state.errorMessage)));
            }
          },
          builder: (context, state) {
            return Column(
              children: [
                _ChatHeader(title: state.title, avatarUrl: state.avatarUrl),
                const Divider(height: 1, color: MerzoxColors.kColorEFEFEF),
                Expanded(
                  child: _ChatBody(state: state, controller: _scrollController),
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

class _ChatBody extends StatelessWidget {
  final ChatState state;
  final ScrollController controller;

  const _ChatBody({required this.state, required this.controller});

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
                    : state.errorMessage,
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'messages.threadEmpty'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MerzoxColors.kColor8D99AE,
              fontSize: 13,
            ),
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
          return _MessageBubble(message: message);
        },
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final MessageApiModel message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.72,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMine
                    ? MerzoxColors.kColorEE6C4D
                    : MerzoxColors.kColorF3F7FA,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(isMine ? 14 : 2),
                  bottomRight: Radius.circular(isMine ? 2 : 14),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.body,
                    style: TextStyle(
                      color: isMine ? Colors.white : MerzoxColors.kColor3B3B3B,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(message.createdAt),
                    style: TextStyle(
                      color: isMine
                          ? Colors.white70
                          : MerzoxColors.kColor8D99AE,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
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
    final initial = label.trim().isEmpty ? '؟' : label.trim().characters.first;

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
              errorBuilder: (_, __, ___) => Center(
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

String _formatTime(DateTime? value) {
  if (value == null) return '';
  final local = value.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final suffix = local.hour >= 12 ? 'PM' : 'AM';

  return '$hour:$minute $suffix';
}
