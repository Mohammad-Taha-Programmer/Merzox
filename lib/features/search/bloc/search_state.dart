import 'package:merzox/services/api_service.dart';

import 'search_refinement.dart';

enum SearchStatus { initial, idle, loading, success, failure }

final class SearchState {
  final SearchStatus status;
  final String query;
  final SearchRefinement refinement;
  final int selectedTab;
  final List<String> history;
  final List<SearchProductApiModel> products;
  final List<SearchBusinessApiModel> businesses;
  final String? errorMessage;

  const SearchState({
    this.status = SearchStatus.initial,
    this.query = '',
    this.refinement = const SearchRefinement(),
    this.selectedTab = 0,
    this.history = const [],
    this.products = const [],
    this.businesses = const [],
    this.errorMessage,
  });

  /// Whether there is anything to search for. Either box will do: somebody who
  /// only knows what they want to buy has said enough.
  bool get hasQuery => query.trim().isNotEmpty || refinement.hasProduct;

  /// Whether the shop box itself has anything in it.
  bool get hasShopQuery => query.trim().isNotEmpty;

  bool get hasExactBusinessMatch {
    final normalizedQuery = query.trim();

    if (normalizedQuery.isEmpty || businesses.length != 1) {
      return false;
    }

    final business = businesses.single;

    if (business.publicId != normalizedQuery) {
      return false;
    }

    return products.every(
      (product) => product.business.publicId == business.publicId,
    );
  }

  SearchState copyWith({
    SearchStatus? status,
    String? query,
    SearchRefinement? refinement,
    int? selectedTab,
    List<String>? history,
    List<SearchProductApiModel>? products,
    List<SearchBusinessApiModel>? businesses,
    String? errorMessage,
  }) {
    return SearchState(
      status: status ?? this.status,
      query: query ?? this.query,
      refinement: refinement ?? this.refinement,
      selectedTab: selectedTab ?? this.selectedTab,
      history: history ?? this.history,
      products: products ?? this.products,
      businesses: businesses ?? this.businesses,
      errorMessage: errorMessage,
    );
  }
}
