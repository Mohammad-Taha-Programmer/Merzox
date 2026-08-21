import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'search_event.dart';
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
    final query = event.query.trim();
    _debounce?.cancel();

    if (query.isEmpty) {
      emit(
        state.copyWith(
          status: SearchStatus.idle,
          query: '',
          products: const [],
          businesses: const [],
          errorMessage: null,
        ),
      );
      return;
    }

    emit(state.copyWith(query: query, status: SearchStatus.loading));
    _debounce = Timer(const Duration(milliseconds: 260), () {
      add(SearchSubmitted(query));
    });
  }

  Future<void> _onSubmitted(
    SearchSubmitted event,
    Emitter<SearchState> emit,
  ) async {
    final query = event.query.trim();
    if (query.isEmpty) return;

    emit(state.copyWith(status: SearchStatus.loading, query: query));

    try {
      final result = await _apiService.searchCatalog(query: query);
      final history = await _saveHistory(query);
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
