import 'package:merzox/services/api_service.dart';

enum SearchStatus { initial, idle, loading, success, failure }

final class SearchState {
  final SearchStatus status;
  final String query;
  final int selectedTab;
  final List<String> history;
  final List<SearchProductApiModel> products;
  final List<SearchBusinessApiModel> businesses;
  final String? errorMessage;

  const SearchState({
    this.status = SearchStatus.initial,
    this.query = '',
    this.selectedTab = 0,
    this.history = const [],
    this.products = const [],
    this.businesses = const [],
    this.errorMessage,
  });

  bool get hasQuery => query.trim().isNotEmpty;

  SearchState copyWith({
    SearchStatus? status,
    String? query,
    int? selectedTab,
    List<String>? history,
    List<SearchProductApiModel>? products,
    List<SearchBusinessApiModel>? businesses,
    String? errorMessage,
  }) {
    return SearchState(
      status: status ?? this.status,
      query: query ?? this.query,
      selectedTab: selectedTab ?? this.selectedTab,
      history: history ?? this.history,
      products: products ?? this.products,
      businesses: businesses ?? this.businesses,
      errorMessage: errorMessage,
    );
  }
}
