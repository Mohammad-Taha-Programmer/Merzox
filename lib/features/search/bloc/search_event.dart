sealed class SearchEvent {
  const SearchEvent();
}

final class SearchStarted extends SearchEvent {
  const SearchStarted();
}

final class SearchQueryChanged extends SearchEvent {
  final String query;

  const SearchQueryChanged(this.query);
}

final class SearchSubmitted extends SearchEvent {
  final String query;

  const SearchSubmitted(this.query);
}

final class SearchHistoryItemSelected extends SearchEvent {
  final String query;

  const SearchHistoryItemSelected(this.query);
}

final class SearchHistoryItemRemoved extends SearchEvent {
  final String query;

  const SearchHistoryItemRemoved(this.query);
}

final class SearchHistoryCleared extends SearchEvent {
  const SearchHistoryCleared();
}

final class SearchTabChanged extends SearchEvent {
  final int index;

  const SearchTabChanged(this.index);
}
