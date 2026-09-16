import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'search_event.dart';
import 'search_refinement.dart';
import 'search_state.dart';

class SearchBloc extends Bloc<SearchEvent, SearchState> {
  static const String historyKey = 'merzox.search.history';
  final ApiService _apiService;
  Timer? _debounce;

  SearchBloc({ApiService? apiService})
    : _apiService = apiService ?? ApiService(),
      super(const SearchState()) {
    on<SearchStarted>(_onStarted);
    on<SearchQueryChanged>(_onQueryChanged);
    on<SearchSubmitted>(_onSubmitted);
    on<SearchHistoryItemSelected>(_onHistorySelected);
    on<SearchHistoryItemRemoved>(_onHistoryRemoved);
    on<SearchHistoryCleared>(_onHistoryCleared);
    on<SearchMatchChanged>(_onMatchChanged);
    on<SearchProductChanged>(_onProductChanged);
    on<SearchProductMatchChanged>(_onProductMatchChanged);
    on<SearchTabChanged>(_onTabChanged);
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }

  Future<void> _onStarted(
    SearchStarted event,
    Emitter<SearchState> emit,
  ) async {
    emit(
      state.copyWith(status: SearchStatus.idle, history: await _loadHistory()),
    );
  }

  void _onQueryChanged(SearchQueryChanged event, Emitter<SearchState> emit) {
    emit(state.copyWith(query: event.query.trim()));
    _searchOrRest(emit);
  }

  void _onMatchChanged(SearchMatchChanged event, Emitter<SearchState> emit) {
    emit(
      state.copyWith(refinement: state.refinement.copyWith(match: event.match)),
    );
    // Straight away, not after the usual pause: a press is a decision, where
    // a keystroke is somebody still deciding.
    _searchOrRest(emit, immediately: true);
  }

  void _onProductChanged(
    SearchProductChanged event,
    Emitter<SearchState> emit,
  ) {
    emit(
      state.copyWith(
        refinement: state.refinement.copyWith(product: event.product.trim()),
      ),
    );
    _searchOrRest(emit);
  }

  void _onProductMatchChanged(
    SearchProductMatchChanged event,
    Emitter<SearchState> emit,
  ) {
    emit(
      state.copyWith(
        refinement: state.refinement.copyWith(productMatch: event.productMatch),
      ),
    );

    // Nothing to re-ask when the box it governs is empty.
    if (state.refinement.hasProduct) _searchOrRest(emit, immediately: true);
  }

  /// Ask again, or go quiet when there is nothing left to ask.
  ///
  /// Both boxes feed this. Emptying one of them is not emptying the search -
  /// a reader who clears the shop name and leaves `جاكيت` is still asking a
  /// question, and answering it with a blank screen would look like a fault.
  void _searchOrRest(Emitter<SearchState> emit, {bool immediately = false}) {
    _debounce?.cancel();

    if (!state.hasQuery) {
      emit(
        state.copyWith(
          status: SearchStatus.idle,
          products: const [],
          businesses: const [],
          errorMessage: null,
        ),
      );
      return;
    }

    emit(state.copyWith(status: SearchStatus.loading));

    if (immediately) {
      add(SearchSubmitted(state.query));
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 260), () {
      add(SearchSubmitted(state.query));
    });
  }

  Future<void> _onSubmitted(
    SearchSubmitted event,
    Emitter<SearchState> emit,
  ) async {
    final query = event.query.trim();
    final SearchRefinement refinement = state.refinement;
    if (query.isEmpty && !refinement.hasProduct) return;

    emit(state.copyWith(status: SearchStatus.loading, query: query));

    try {
      final result = await _apiService.searchCatalog(
        query: query,
        match: refinement.match.wire,
        product: refinement.product,
        productMatch: refinement.productMatch.wire,
      );
      // What goes in the list is what the reader typed in the shop box. A
      // search for goods alone has no name to remember.
      final history = query.isEmpty ? state.history : await _saveHistory(query);
      emit(
        state.copyWith(
          status: SearchStatus.success,
          query: result.query.isEmpty ? query : result.query,
          history: history,
          products: result.products,
          businesses: result.businesses,
          errorMessage: null,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: SearchStatus.failure,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  void _onHistorySelected(
    SearchHistoryItemSelected event,
    Emitter<SearchState> emit,
  ) {
    add(SearchSubmitted(event.query));
  }

  Future<void> _onHistoryRemoved(
    SearchHistoryItemRemoved event,
    Emitter<SearchState> emit,
  ) async {
    final next = [...state.history]..remove(event.query);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(historyKey, next);
    emit(state.copyWith(history: next));
  }

  Future<void> _onHistoryCleared(
    SearchHistoryCleared event,
    Emitter<SearchState> emit,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(historyKey);
    emit(state.copyWith(history: const []));
  }

  void _onTabChanged(SearchTabChanged event, Emitter<SearchState> emit) {
    emit(state.copyWith(selectedTab: event.index));
  }

  Future<List<String>> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(historyKey) ?? const [];
  }

  Future<List<String>> _saveHistory(String query) async {
    final current = await _loadHistory();
    final next = [
      query,
      ...current.where((item) => item != query),
    ].take(12).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(historyKey, next);
    return next;
  }
}
