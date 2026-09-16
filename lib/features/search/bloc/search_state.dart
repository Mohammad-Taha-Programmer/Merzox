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

  /// Which tab a fresh result should open on.
  ///
  /// The answer the reader is most likely to have been looking for. Shops when
  /// any shop matched - including a search by telephone number, which names a
  /// shop and never a thing on its shelves - and goods only when the words
  /// found goods and no shop at all. With nothing found there is nothing to
  /// choose between, and shops is where the screen has always started.
  static const int productsTab = 0;
  static const int storesTab = 1;

  static int tabFor({required bool hasBusinesses, required bool hasProducts}) {
    if (hasBusinesses) return storesTab;
    if (hasProducts) return productsTab;

    return storesTab;
  }

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
