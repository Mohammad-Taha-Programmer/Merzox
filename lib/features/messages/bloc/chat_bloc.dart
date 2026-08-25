import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/api_service.dart';
import '../../../core/auth/auth_session_service.dart';
import 'chat_event.dart';
import 'chat_state.dart';

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final ApiService _apiService;
  final AuthSessionService _authSessionService;

  ChatBloc({
    ApiService? apiService,
    AuthSessionService authSessionService = const AuthSessionService(),
    String conversationId = '',
    String title = '',
    String avatarUrl = '',
  }) : _apiService = apiService ?? ApiService(),
       _authSessionService = authSessionService,
       super(
         ChatState(
           conversationId: conversationId,
           title: title,
           avatarUrl: avatarUrl,
         ),
       ) {
    on<ChatStarted>(_onStarted);
    on<ChatOpenedForBusiness>(_onOpenedForBusiness);
    on<ChatMessageSent>(_onMessageSent);
    on<ChatOlderMessagesRequested>(_onOlderMessagesRequested);
    on<ChatRefreshRequested>(_onRefreshRequested);
  }

  Future<void> _onStarted(ChatStarted event, Emitter<ChatState> emit) async {
    await _loadFirstPage(emit);
  }

  Future<void> _onRefreshRequested(
    ChatRefreshRequested event,
    Emitter<ChatState> emit,
  ) async {
    await _loadFirstPage(emit);
  }

  /// Entry point from a store page: the thread is created on demand, then the
  /// history loads exactly as it would from the inbox.
  Future<void> _onOpenedForBusiness(
    ChatOpenedForBusiness event,
    Emitter<ChatState> emit,
  ) async {
    emit(state.copyWith(status: ChatStatus.loading, errorMessage: ''));

    try {
      final conversation = await _apiService.openConversation(
        token: await _token(),
        businessId: event.businessId,
      );
      emit(
        state.copyWith(
          conversationId: conversation.id,
          title: conversation.title,
          avatarUrl: conversation.avatarUrl,
        ),
      );
      await _loadFirstPage(emit);
    } catch (error) {
      emit(
        state.copyWith(
          status: ChatStatus.failure,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  Future<void> _loadFirstPage(Emitter<ChatState> emit) async {
    if (state.conversationId.isEmpty) {
      emit(
        state.copyWith(
          status: ChatStatus.failure,
          errorMessage: 'messages.openError',
        ),
      );
      return;
    }

    emit(state.copyWith(status: ChatStatus.loading, errorMessage: ''));

    try {
      final token = await _token();
      final response = await _apiService.conversationMessages(
        token: token,
        conversationId: state.conversationId,
      );

      emit(
        state.copyWith(
          status: ChatStatus.ready,
          title: response.conversation.title.isEmpty
              ? state.title
              : response.conversation.title,
          avatarUrl: response.conversation.avatarUrl,
          messages: response.messages,
          page: response.page,
          hasMore: response.hasMore,
        ),
      );

      // Marking the thread read is a second, independent operation. Its
      // failure must not hide messages that already loaded, but it must not be
      // reported as a success either - the inbox stays the unread authority
      // and refreshes from the backend when this screen is popped.
      try {
        await _apiService.markConversationRead(
          token: token,
          conversationId: state.conversationId,
        );
        emit(state.copyWith(readSyncFailed: false));
      } catch (_) {
        emit(state.copyWith(readSyncFailed: true));
      }
    } catch (error) {
      emit(
        state.copyWith(
          status: ChatStatus.failure,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  Future<void> _onOlderMessagesRequested(
    ChatOlderMessagesRequested event,
    Emitter<ChatState> emit,
  ) async {
    if (!state.hasMore || state.status != ChatStatus.ready) return;

    emit(state.copyWith(status: ChatStatus.loadingMore));
    try {
      final response = await _apiService.conversationMessages(
        token: await _token(),
        conversationId: state.conversationId,
        page: state.page + 1,
      );
      emit(
        state.copyWith(
          status: ChatStatus.ready,
          messages: [...response.messages, ...state.messages],
          page: response.page,
          hasMore: response.hasMore,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: ChatStatus.ready,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  Future<void> _onMessageSent(
    ChatMessageSent event,
    Emitter<ChatState> emit,
  ) async {
    final body = event.body.trim();
    if (body.isEmpty || state.conversationId.isEmpty) return;
    if (state.status == ChatStatus.sending) return;

    emit(state.copyWith(status: ChatStatus.sending, errorMessage: ''));

    try {
      final message = await _apiService.sendMessage(
        token: await _token(),
        conversationId: state.conversationId,
        body: body,
      );
      emit(
        state.copyWith(
          status: ChatStatus.ready,
          messages: [...state.messages, message],
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: ChatStatus.ready,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
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

    return token;
  }
}
