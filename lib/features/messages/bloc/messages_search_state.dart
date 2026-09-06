import '../../../services/api_service.dart';

enum MessagesSearchStatus { idle, searching, ready, failure }

/// What the search box in the inbox is currently showing.
///
/// [query] is what the reader typed, not what the server last answered: the
/// field must never jump back to an older word while a request is in flight.
final class MessagesSearchState {
  final MessagesSearchStatus status;

  /// Whether the box is open at all. Closed is not the same as empty - a
  /// reader who clears the text still expects to be searching.
  final bool open;

  final String query;

  /// The query the results below actually answer.
  final String answeredQuery;

  /// Threads whose other side is named like the query.
  final List<ConversationApiModel> people;

  /// Threads where something like the query was said.
  final List<ConversationMessageMatchApiModel> messages;

  final String errorMessage;

  const MessagesSearchState({
    this.status = MessagesSearchStatus.idle,
    this.open = false,
    this.query = '',
    this.answeredQuery = '',
    this.people = const <ConversationApiModel>[],
    this.messages = const <ConversationMessageMatchApiModel>[],
    this.errorMessage = '',
  });

  /// Whether the inbox list should stand aside for results.
  ///
  /// An open box with nothing typed still shows the inbox: the reader has
  /// asked to search, not to be shown nothing.
  bool get showsResults => open && query.trim().isNotEmpty;

  bool get hasResults => people.isNotEmpty || messages.isNotEmpty;

  /// Nothing found, and the server has actually said so about THIS query.
  /// Without the second half the screen announces "no results" in the pause
  /// between a keystroke and its answer.
  bool get foundNothing =>
      status == MessagesSearchStatus.ready &&
      answeredQuery == query.trim() &&
      !hasResults;

  MessagesSearchState copyWith({
    MessagesSearchStatus? status,
    bool? open,
    String? query,
    String? answeredQuery,
    List<ConversationApiModel>? people,
    List<ConversationMessageMatchApiModel>? messages,
    String? errorMessage,
  }) {
    return MessagesSearchState(
      status: status ?? this.status,
      open: open ?? this.open,
      query: query ?? this.query,
      answeredQuery: answeredQuery ?? this.answeredQuery,
      people: people ?? this.people,
      messages: messages ?? this.messages,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
