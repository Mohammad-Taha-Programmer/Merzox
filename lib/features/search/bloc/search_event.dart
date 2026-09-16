import 'search_refinement.dart';

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

/// The reader changed where the shop name has to sit.
final class SearchMatchChanged extends SearchEvent {
  final SearchMatch match;

  const SearchMatchChanged(this.match);
}

/// The reader typed, or cleared, the goods they want the shop to sell.
final class SearchProductChanged extends SearchEvent {
  final String product;

  const SearchProductChanged(this.product);
}

/// The reader changed how the goods are matched.
final class SearchProductMatchChanged extends SearchEvent {
  final SearchMatch productMatch;

  const SearchProductMatchChanged(this.productMatch);
}

final class SearchTabChanged extends SearchEvent {
  final int index;

  const SearchTabChanged(this.index);
}
