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

  /// Set when the thread loaded but the server refused to mark it read. The
  /// conversation stays usable; this only records that the read receipt did
  /// not land, so the UI never implies a synchronisation that did not happen.
  final bool readSyncFailed;

  /// What the reader searched for, when they arrived here from a result.
  ///
  /// Kept so every occurrence stays marked while they walk between them - a
  /// highlight that only marked the one being visited would make the others
  /// invisible in exactly the moment they are looking for them.
  final String highlightQuery;

  /// The places to stand, oldest first, as the search found them.
  final List<String> matchIds;

  /// Which of [matchIds] the reader is at. -1 when they arrived normally.
  final int matchIndex;

  /// Whether the thread was actually paged back far enough to hold the first
  /// match. False says the scroll cannot honour the tap, which the screen
  /// reports rather than silently landing somewhere else.
  final bool anchorReached;

  const ChatState({
    this.status = ChatStatus.initial,
    this.conversationId = '',
    this.title = '',
    this.avatarUrl = '',
    this.messages = const [],
    this.page = 1,
    this.hasMore = false,
    this.errorMessage = '',
    this.readSyncFailed = false,
    this.highlightQuery = '',
    this.matchIds = const <String>[],
    this.matchIndex = -1,
    this.anchorReached = true,
  });

  /// Whether the reader arrived here from a search result.
  bool get isWalkingMatches => matchIds.isNotEmpty;

  /// The message the view should be showing, or empty when there is none.
  String get currentMatchId => matchIndex >= 0 && matchIndex < matchIds.length
      ? matchIds[matchIndex]
      : '';

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
    bool? readSyncFailed,
    String? highlightQuery,
    List<String>? matchIds,
    int? matchIndex,
    bool? anchorReached,
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
      readSyncFailed: readSyncFailed ?? this.readSyncFailed,
      highlightQuery: highlightQuery ?? this.highlightQuery,
      matchIds: matchIds ?? this.matchIds,
      matchIndex: matchIndex ?? this.matchIndex,
      anchorReached: anchorReached ?? this.anchorReached,
    );
  }
}
