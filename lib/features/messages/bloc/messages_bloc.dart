import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/api_service.dart';
import '../../../core/auth/auth_session_service.dart';
import 'messages_event.dart';
import 'messages_state.dart';

class MessagesBloc extends Bloc<MessagesEvent, MessagesState> {
  final ApiService _apiService;
  final AuthSessionService _authSessionService;

  /// The same list serves the customer inbox and the merchant inbox; only the
  /// endpoint differs, so the side is fixed when the bloc is created.
  final bool merchantMode;

  MessagesBloc({
    ApiService? apiService,
    AuthSessionService authSessionService = const AuthSessionService(),
    this.merchantMode = false,
  }) : _apiService = apiService ?? ApiService(),
       _authSessionService = authSessionService,
       super(const MessagesState()) {
    on<MessagesStarted>(_onStarted);
    on<MessagesFilterChanged>(_onFilterChanged);
    on<MessagesRefreshRequested>(_onRefreshRequested);
    on<MessagesLoadMoreRequested>(_onLoadMoreRequested);
  }

  Future<void> _onStarted(
    MessagesStarted event,
    Emitter<MessagesState> emit,
  ) async {
    await _loadFirstPage(emit, state.filter);
  }

  Future<void> _onFilterChanged(
    MessagesFilterChanged event,
    Emitter<MessagesState> emit,
  ) async {
    if (event.filter == state.filter &&
        state.status != MessagesStatus.failure) {
      return;
    }
    await _loadFirstPage(emit, event.filter);
  }

  Future<void> _onRefreshRequested(
    MessagesRefreshRequested event,
    Emitter<MessagesState> emit,
  ) async {
    await _loadFirstPage(emit, state.filter);
  }

  Future<void> _loadFirstPage(
    Emitter<MessagesState> emit,
    MessagesFilter filter,
  ) async {
    emit(
      state.copyWith(
        status: MessagesStatus.loading,
        filter: filter,
        conversations: const [],
        page: 1,
        hasMore: false,
        errorMessage: '',
      ),
    );

    try {
      final response = await _fetch(filter: filter, page: 1);
      emit(
        state.copyWith(
          status: MessagesStatus.ready,
          conversations: response.conversations,
          unreadConversationCount: response.unreadConversationCount,
          page: response.page,
          hasMore: response.hasMore,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: MessagesStatus.failure,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  Future<void> _onLoadMoreRequested(
    MessagesLoadMoreRequested event,
    Emitter<MessagesState> emit,
  ) async {
    if (!state.hasMore || state.status != MessagesStatus.ready) return;

    emit(state.copyWith(status: MessagesStatus.loadingMore));
    try {
      final response = await _fetch(filter: state.filter, page: state.page + 1);
      emit(
        state.copyWith(
          status: MessagesStatus.ready,
          conversations: [...state.conversations, ...response.conversations],
          unreadConversationCount: response.unreadConversationCount,
          page: response.page,
          hasMore: response.hasMore,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: MessagesStatus.ready,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  Future<ConversationListApiResponse> _fetch({
    required MessagesFilter filter,
    required int page,
  }) async {
    final token = await _token();

    if (merchantMode) {
      return _apiService.merchantConversations(
        token: token,
        unreadOnly: filter.unreadOnly,
        page: page,
      );
    }

    return _apiService.conversations(
      token: token,
      unreadOnly: filter.unreadOnly,
      page: page,
    );
  }

  /// Session truth lives in [AuthSessionService]: a stale token without an
  /// active session, or a blank one, resolves to unauthenticated here rather
  /// than being re-interpreted per bloc.
  Future<String> _token() async {
    final session = await _authSessionService.read();
    final token = session.token;

    if (token == null) {
      throw StateError('Authentication required');
    }

    // The merchant inbox is a different endpoint, not a different view of the
    // same data, so the session must prove the role before it is requested.
    if (merchantMode && !session.isBusiness) {
      throw StateError('A business account is required');
    }

    return token;
  }
}
