import '../../../services/api_service.dart';
import 'messages_event.dart';

enum MessagesStatus { initial, loading, ready, loadingMore, failure }

final class MessagesState {
  final MessagesStatus status;
  final MessagesFilter filter;
  final List<ConversationApiModel> conversations;
  final int unreadConversationCount;
  final int page;
  final bool hasMore;
  final String errorMessage;

  const MessagesState({
    this.status = MessagesStatus.initial,
    this.filter = MessagesFilter.all,
    this.conversations = const [],
    this.unreadConversationCount = 0,
    this.page = 1,
    this.hasMore = false,
    this.errorMessage = '',
  });

  bool get isEmpty => status == MessagesStatus.ready && conversations.isEmpty;

  MessagesState copyWith({
    MessagesStatus? status,
    MessagesFilter? filter,
    List<ConversationApiModel>? conversations,
    int? unreadConversationCount,
    int? page,
    bool? hasMore,
    String? errorMessage,
  }) {
    return MessagesState(
      status: status ?? this.status,
      filter: filter ?? this.filter,
      conversations: conversations ?? this.conversations,
      unreadConversationCount:
          unreadConversationCount ?? this.unreadConversationCount,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
