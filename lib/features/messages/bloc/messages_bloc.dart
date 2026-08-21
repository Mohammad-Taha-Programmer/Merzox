import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/api_service.dart';
import '../../authentication/bloc/auth_bloc.dart';
import 'messages_event.dart';
import 'messages_state.dart';

class MessagesBloc extends Bloc<MessagesEvent, MessagesState> {
  final ApiService _apiService;

  /// The same list serves the customer inbox and the merchant inbox; only the
  /// endpoint differs, so the side is fixed when the bloc is created.
  final bool merchantMode;

  MessagesBloc({ApiService? apiService, this.merchantMode = false})
    : _apiService = apiService ?? ApiService(),
      super(const MessagesState()) {
    on<MessagesStarted>(_onStarted);
    on<MessagesFilterChanged>(_onFilterChanged);
    on<MessagesRefreshRequested>(_onRefreshRequested);
    on<MessagesLoadMoreRequested>(_onLoadMoreRequested);
    on<MessagesThreadRead>(_onThreadRead);
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

  /// Clearing the badge locally keeps the inbox in step with a thread the user
  /// just read, without paying for another round trip.
  void _onThreadRead(MessagesThreadRead event, Emitter<MessagesState> emit) {
    final existing = state.conversations
        .where((conversation) => conversation.id == event.conversationId)
        .firstOrNull;

    if (existing == null || !existing.hasUnread) return;

    final updated = [
      for (final conversation in state.conversations)
        if (conversation.id == event.conversationId)
          ConversationApiModel(
            id: conversation.id,
            title: conversation.title,
            avatarUrl: conversation.avatarUrl,
            business: conversation.business,
            customer: conversation.customer,
            lastMessage: conversation.lastMessage,
            unreadCount: 0,
            messageCount: conversation.messageCount,
            updatedAt: conversation.updatedAt,
          )
        else
          conversation,
    ];

    emit(
      state.copyWith(
        conversations: state.filter == MessagesFilter.unread
            ? updated
                  .where(
                    (conversation) => conversation.id != event.conversationId,
                  )
                  .toList()
            : updated,
        unreadConversationCount: state.unreadConversationCount > 0
            ? state.unreadConversationCount - 1
            : 0,
      ),
    );
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

  Future<String> _token() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(AuthBloc.tokenKey);
    if (token == null || token.isEmpty) {
      throw StateError('Authentication required');
    }
    return token;
  }
}
