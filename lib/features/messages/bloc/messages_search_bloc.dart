import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/auth/auth_session_service.dart';
import '../../../services/api_service.dart';
import 'messages_search_event.dart';
import 'messages_search_state.dart';

/// How long the box waits before asking, so a typed word is one request and
/// not one per letter. The keyboard's search key does not wait.
const Duration kMessagesSearchDebounce = Duration(milliseconds: 350);

/// Searching the inbox.
///
/// Kept apart from `MessagesBloc` rather than folded into it: the inbox is a
/// paged, realtime-invalidated list and the search is a single question with a
/// single answer. Sharing one state would have every keystroke racing the
/// realtime refresh for the same field.
class MessagesSearchBloc
    extends Bloc<MessagesSearchEvent, MessagesSearchState> {
  final ApiService _apiService;
  final AuthSessionService _authSessionService;

  /// Whether this reads the shop's threads or the reader's own.
  final bool businessAudience;

  Timer? _debounce;

  /// Which question the screen is waiting on.
  ///
  /// Answers are checked against it before they are shown: two searches can be
  /// in the air at once, and the slower one must not land on top of the newer.
  int _asked = 0;

  MessagesSearchBloc({
    ApiService? apiService,
    AuthSessionService authSessionService = const AuthSessionService(),
    this.businessAudience = false,
  }) : _apiService = apiService ?? ApiService(),
       _authSessionService = authSessionService,
       super(const MessagesSearchState()) {
    on<MessagesSearchOpened>(_onOpened);
    on<MessagesSearchClosed>(_onClosed);
    on<MessagesSearchQueryChanged>(_onQueryChanged);
    on<MessagesSearchSubmitted>(_onSubmitted);
  }

  void _onOpened(
    MessagesSearchOpened event,
    Emitter<MessagesSearchState> emit,
  ) {
    emit(state.copyWith(open: true));
  }

  void _onClosed(
    MessagesSearchClosed event,
    Emitter<MessagesSearchState> emit,
  ) {
    _debounce?.cancel();
    // A landing answer to the question just abandoned must not reopen the
    // results behind the closed box.
    _asked += 1;
    emit(const MessagesSearchState());
  }

  void _onQueryChanged(
    MessagesSearchQueryChanged event,
    Emitter<MessagesSearchState> emit,
  ) {
    _debounce?.cancel();

    // The field is echoed immediately; only the asking waits.
    emit(state.copyWith(query: event.query, errorMessage: ''));

    if (event.query.trim().isEmpty) {
      _asked += 1;
      emit(
        state.copyWith(
          status: MessagesSearchStatus.idle,
          answeredQuery: '',
          people: const <ConversationApiModel>[],
          messages: const <ConversationMessageMatchApiModel>[],
        ),
      );
      return;
    }

    _debounce = Timer(kMessagesSearchDebounce, () {
      if (isClosed) return;
      add(MessagesSearchSubmitted(event.query));
    });
  }

  Future<void> _onSubmitted(
    MessagesSearchSubmitted event,
    Emitter<MessagesSearchState> emit,
  ) async {
    _debounce?.cancel();

    final String asked = event.query.trim();
    if (asked.isEmpty) return;

    _asked += 1;
    final int mine = _asked;

    emit(
      state.copyWith(
        query: event.query,
        status: MessagesSearchStatus.searching,
      ),
    );

    try {
      final ConversationSearchApiResponse response = await _apiService
          .searchConversations(
            token: await _token(),
            query: asked,
            businessAudience: businessAudience,
          );

      if (mine != _asked || emit.isDone) return;

      emit(
        state.copyWith(
          status: MessagesSearchStatus.ready,
          answeredQuery: asked,
          people: response.people,
          messages: response.messages,
          errorMessage: '',
        ),
      );
    } catch (error) {
      if (mine != _asked || emit.isDone) return;

      // The last proven results are kept on screen. A dropped connection is
      // not evidence that what was found a moment ago has stopped existing.
      emit(
        state.copyWith(
          status: MessagesSearchStatus.failure,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  Future<String> _token() async {
    final session = await _authSessionService.read();
    final String? token = session.token;

    if (token == null) {
      throw StateError('Authentication required');
    }

    return token;
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }
}
