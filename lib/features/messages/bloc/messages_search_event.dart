sealed class MessagesSearchEvent {
  const MessagesSearchEvent();
}

/// The magnifier was tapped.
final class MessagesSearchOpened extends MessagesSearchEvent {
  const MessagesSearchOpened();
}

/// The box was closed, which also throws the results away: reopening it should
/// not show yesterday's answer to a word the reader has forgotten typing.
final class MessagesSearchClosed extends MessagesSearchEvent {
  const MessagesSearchClosed();
}

final class MessagesSearchQueryChanged extends MessagesSearchEvent {
  final String query;

  const MessagesSearchQueryChanged(this.query);
}

/// Raised by the debounce, or by the keyboard's search key, which does not
/// wait.
final class MessagesSearchSubmitted extends MessagesSearchEvent {
  final String query;

  const MessagesSearchSubmitted(this.query);
}
