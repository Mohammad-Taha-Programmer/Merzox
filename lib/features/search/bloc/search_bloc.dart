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
    // Read first, then emit. Written the other way round - `state.copyWith(...,
    // history: await _loadHistory())` - Dart evaluates `state` before it
    // evaluates the argument, so what is emitted is built on a snapshot taken
    // before the await and everything written during it is lost. A reader who
    // typed while the list of past searches was loading had their words wiped
    // by the arrival of that list.
    final List<String> history = await _loadHistory();

    emit(state.copyWith(status: SearchStatus.idle, history: history));
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
      // The answer to a question nobody is asking any more is thrown away.
      //
      // Typing `بتول` a letter at a time sends more than one search, because
      // each pause longer than the debounce sends one. `ب` is the broad
      // search and therefore the slow one, so it comes back last - and
      // without this it overwrote the narrow answer already on the screen
      // with forty shops that had nothing to do with what was typed.
      if (_isStale(query, refinement)) return;

      // What goes in the list is what the reader typed in the shop box. A
      // search for goods alone has no name to remember.
      final history = query.isEmpty ? state.history : await _saveHistory(query);

      // Saving touches storage, which is another await and another chance for
      // the question to have changed under it.
      if (_isStale(query, refinement)) return;
      emit(
        state.copyWith(
          status: SearchStatus.success,
          query: result.query.isEmpty ? query : result.query,
          history: history,
          products: result.products,
          businesses: result.businesses,
          // Each answer opens on the tab that holds it. A reader who then
          // picks the other tab keeps it until the next answer arrives, which
          // is a new question and a new best guess.
          selectedTab: SearchState.tabFor(
            shopsMatchedThemselves: result.shopsMatchedThemselves,
            hasProducts: result.products.isNotEmpty,
          ),
          errorMessage: null,
        ),
      );
    } catch (error) {
      // A failure is as stale as a success: one search failing says nothing
      // about the one that replaced it.
      if (_isStale(query, refinement)) return;

      emit(
        state.copyWith(
          status: SearchStatus.failure,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  /// Whether what came back answers what is being asked now.
  ///
  /// Both halves matter: the words, and how they were to be matched. Changing
  /// `contains` to `starts` asks a different question of the same words, and
  /// the old answer to it is just as wrong.
  bool _isStale(String query, SearchRefinement refinement) {
    if (isClosed) return true;

    return query != state.query || refinement != state.refinement;
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
