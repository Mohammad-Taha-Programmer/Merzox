import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/auth/auth_session_service.dart';
import '../../../services/api_service.dart';
import '../../../services/realtime_service.dart';
import 'chat_event.dart';
import 'chat_state.dart';

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final ApiService _apiService;
  final AuthSessionService _authSessionService;

  StreamSubscription<RealtimeMessageInvalidation>?
  _messageInvalidationSubscription;

  StreamSubscription<RealtimeConnectionStatus>? _connectionStatusSubscription;

  Timer? _realtimeDebounce;

  bool _realtimeSyncInFlight = false;
  bool _realtimeSyncPending = false;
  bool _realtimeWasDisconnected = false;

  ChatBloc({
    ApiService? apiService,
    AuthSessionService authSessionService = const AuthSessionService(),
    Stream<RealtimeMessageInvalidation>? realtimeMessageInvalidations,
    Stream<RealtimeConnectionStatus>? realtimeConnectionStatuses,
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
    on<ChatRealtimeSyncRequested>(_onRealtimeSyncRequested);

    _bindRealtime(
      messageInvalidations: realtimeMessageInvalidations,
      connectionStatuses: realtimeConnectionStatuses,
    );
  }

  void _bindRealtime({
    required Stream<RealtimeMessageInvalidation>? messageInvalidations,
    required Stream<RealtimeConnectionStatus>? connectionStatuses,
  }) {
    _messageInvalidationSubscription = messageInvalidations?.listen((
      invalidation,
    ) {
      // conversation-read is intentionally ignored by the open chat. It is an
      // inbox/badge invalidation for the reader's other sessions. Reacting to
      // it here would cause mark-read -> realtime -> mark-read loops.
      if (invalidation.reason != 'message-created') {
        return;
      }

      final conversationId = state.conversationId;

      if (conversationId.isEmpty ||
          invalidation.conversationId != conversationId) {
        return;
      }

      _scheduleRealtimeSync();
    });

    if (connectionStatuses != null) {
      // If this BLoC is born while transport is still connecting, the first
      // connected signal should recover any REST load that failed meanwhile.
      _realtimeWasDisconnected = true;

      _connectionStatusSubscription = connectionStatuses.listen((status) {
        if (status == RealtimeConnectionStatus.disconnected) {
          _realtimeWasDisconnected = true;
          return;
        }

        if (status == RealtimeConnectionStatus.connected &&
            _realtimeWasDisconnected) {
          _realtimeWasDisconnected = false;
          _scheduleRealtimeSync();
        }
      });
    }
  }

  void _scheduleRealtimeSync() {
    _realtimeDebounce?.cancel();

    _realtimeDebounce = Timer(const Duration(milliseconds: 90), () {
      if (!isClosed) {
        add(const ChatRealtimeSyncRequested());
      }
    });
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

      await _markReadBestEffort(emit, token);
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
    if (!state.hasMore || state.status != ChatStatus.ready) {
      return;
    }

    emit(state.copyWith(status: ChatStatus.loadingMore));

    try {
      final response = await _apiService.conversationMessages(
        token: await _token(),
        conversationId: state.conversationId,
        page: state.page + 1,
      );

      // Offset paging can overlap when a new realtime message shifts page
      // boundaries. Merge by the server message id instead of concatenating
      // blindly, while keeping older messages before the already-loaded set.
      final merged = _mergeOrdered(response.messages, state.messages);

      emit(
        state.copyWith(
          status: ChatStatus.ready,
          messages: merged,
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

    if (body.isEmpty || state.conversationId.isEmpty) {
      return;
    }

    if (state.status == ChatStatus.sending) {
      return;
    }

    emit(state.copyWith(status: ChatStatus.sending, errorMessage: ''));

    try {
      final message = await _apiService.sendMessage(
        token: await _token(),
        conversationId: state.conversationId,
        body: body,
      );

      // The sender receives the same realtime invalidation as the counterpart.
      // If its realtime REST resync wins the race, the HTTP response must not
      // append the same message a second time.
      final merged = _mergeOrdered(state.messages, [message]);

      emit(state.copyWith(status: ChatStatus.ready, messages: merged));
    } catch (error) {
      emit(
        state.copyWith(
          status: ChatStatus.ready,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  Future<void> _onRealtimeSyncRequested(
    ChatRealtimeSyncRequested event,
    Emitter<ChatState> emit,
  ) async {
    if (state.conversationId.isEmpty) {
      return;
    }

    if (_realtimeSyncInFlight) {
      _realtimeSyncPending = true;
      return;
    }

    _realtimeSyncInFlight = true;

    try {
      await _syncNewestPage(emit);
    } finally {
      _realtimeSyncInFlight = false;

      if (_realtimeSyncPending) {
        _realtimeSyncPending = false;
        _scheduleRealtimeSync();
      }
    }
  }

  Future<void> _syncNewestPage(Emitter<ChatState> emit) async {
    final conversationId = state.conversationId;

    if (conversationId.isEmpty) {
      return;
    }

    try {
      final token = await _token();

      final response = await _apiService.conversationMessages(
        token: token,
        conversationId: conversationId,
        page: 1,
      );

      // Existing history remains in place. Page one only replaces overlapping
      // server entities and appends genuinely new ids at the end.
      final merged = _mergeOrdered(state.messages, response.messages);

      final loadedPage = state.page < 1 ? 1 : state.page;

      emit(
        state.copyWith(
          status: ChatStatus.ready,
          title: response.conversation.title.isEmpty
              ? state.title
              : response.conversation.title,
          avatarUrl: response.conversation.avatarUrl,
          messages: merged,
          page: loadedPage,
          hasMore: loadedPage == 1 ? response.hasMore : state.hasMore,
          errorMessage: '',
        ),
      );

      await _markReadBestEffort(emit, token);
    } catch (_) {
      // Realtime is an invalidation channel, not the source of truth. A failed
      // background resync leaves the already-rendered authoritative state in
      // place; reconnect or manual refresh will retry.
    }
  }

  Future<void> _markReadBestEffort(
    Emitter<ChatState> emit,
    String token,
  ) async {
    try {
      await _apiService.markConversationRead(
        token: token,
        conversationId: state.conversationId,
      );

      emit(state.copyWith(readSyncFailed: false));
    } catch (_) {
      emit(state.copyWith(readSyncFailed: true));
    }
  }

  /// Merges two already-ordered message ranges.
  ///
  /// The first list establishes the order. A duplicate appearing in [second]
  /// replaces the value at that same position, allowing fresher REST state
  /// such as readAt to win without creating a second row.
  List<MessageApiModel> _mergeOrdered(
    List<MessageApiModel> first,
    List<MessageApiModel> second,
  ) {
    final order = <String>[];
    final byId = <String, MessageApiModel>{};

    void absorb(Iterable<MessageApiModel> source) {
      for (final message in source) {
        final id = message.id;

        if (id.isEmpty) {
          // A valid Merzox message always has an id. Keeping an invalid entity
          // out of realtime merge is safer than collapsing several bad rows
          // onto one empty-key entry.
          continue;
        }

        if (!byId.containsKey(id)) {
          order.add(id);
        }

        byId[id] = message;
      }
    }

    absorb(first);
    absorb(second);

    return [
      for (final id in order)
        if (byId[id] case final message?) message,
    ];
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

  @override
  Future<void> close() async {
    _realtimeDebounce?.cancel();

    await _messageInvalidationSubscription?.cancel();
    await _connectionStatusSubscription?.cancel();

    await super.close();
  }
}
