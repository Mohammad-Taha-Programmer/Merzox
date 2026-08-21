import '../../../services/api_service.dart';

enum ChatStatus { initial, loading, ready, loadingMore, sending, failure }

final class ChatState {
  final ChatStatus status;
  final String conversationId;
  final String title;
  final String avatarUrl;

  /// Oldest first, matching the order the thread is drawn in.
  final List<MessageApiModel> messages;
  final int page;
  final bool hasMore;
  final String errorMessage;

  const ChatState({
    this.status = ChatStatus.initial,
    this.conversationId = '',
    this.title = '',
    this.avatarUrl = '',
    this.messages = const [],
    this.page = 1,
    this.hasMore = false,
    this.errorMessage = '',
  });

  bool get isBusy =>
      status == ChatStatus.loading || status == ChatStatus.sending;

  ChatState copyWith({
    ChatStatus? status,
    String? conversationId,
    String? title,
    String? avatarUrl,
    List<MessageApiModel>? messages,
    int? page,
    bool? hasMore,
    String? errorMessage,
  }) {
    return ChatState(
      status: status ?? this.status,
      conversationId: conversationId ?? this.conversationId,
      title: title ?? this.title,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      messages: messages ?? this.messages,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
