import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/auth/auth_session_service.dart';
import '../../../services/api_service.dart';
import '../../../services/realtime_service.dart';
import 'messages_event.dart';
import 'messages_state.dart';

class MessagesBloc extends Bloc<MessagesEvent, MessagesState> {
  final ApiService _apiService;
  final AuthSessionService _authSessionService;

  /// The same list serves the customer inbox and the merchant inbox; only the
  /// endpoint differs, so the side is fixed when the bloc is created.
  final bool merchantMode;

  StreamSubscription<RealtimeMessageInvalidation>?
  _messageInvalidationSubscription;

  StreamSubscription<RealtimeConnectionStatus>? _connectionStatusSubscription;

  Timer? _realtimeDebounce;

  bool _realtimeWasDisconnected = false;
  bool _realtimeSyncInFlight = false;
  bool _realtimeSyncPending = false;

  MessagesBloc({
    ApiService? apiService,
    AuthSessionService authSessionService = const AuthSessionService(),
    Stream<RealtimeMessageInvalidation>? realtimeMessageInvalidations,
    Stream<RealtimeConnectionStatus>? realtimeConnectionStatuses,
    this.merchantMode = false,
  }) : _apiService = apiService ?? ApiService(),
       _authSessionService = authSessionService,
       super(const MessagesState()) {
    on<MessagesStarted>(_onStarted);
    on<MessagesFilterChanged>(_onFilterChanged);
    on<MessagesRefreshRequested>(_onRefreshRequested);
    on<MessagesLoadMoreRequested>(_onLoadMoreRequested);
    on<MessagesRealtimeSyncRequested>(_onRealtimeSyncRequested);

    _bindRealtime(
      messageInvalidations: realtimeMessageInvalidations,
      connectionStatuses: realtimeConnectionStatuses,
    );
  }

  void _bindRealtime({
    required Stream<RealtimeMessageInvalidation>? messageInvalidations,
    required Stream<RealtimeConnectionStatus>? connectionStatuses,
  }) {
    _messageInvalidationSubscription = messageInvalidations?.listen((_) {
      // Both message-created and conversation-read change the authoritative
      // inbox summary/unread truth, so either one invalidates page one.
      _scheduleRealtimeSync();
    });

    if (connectionStatuses != null) {
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
        add(const MessagesRealtimeSyncRequested());
      }
    });
  }

  void _drainPendingRealtimeSync() {
    if (!_realtimeSyncPending || _realtimeSyncInFlight || isClosed) {
      return;
    }

    _realtimeSyncPending = false;
    _scheduleRealtimeSync();
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
    } finally {
      _drainPendingRealtimeSync();
    }
  }

  Future<void> _onLoadMoreRequested(
    MessagesLoadMoreRequested event,
    Emitter<MessagesState> emit,
  ) async {
    if (!state.hasMore || state.status != MessagesStatus.ready) {
      return;
    }

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
    } finally {
      _drainPendingRealtimeSync();
    }
  }

  Future<void> _onRealtimeSyncRequested(
    MessagesRealtimeSyncRequested event,
    Emitter<MessagesState> emit,
  ) async {
    if (_realtimeSyncInFlight) {
      _realtimeSyncPending = true;
      return;
    }

    if (state.status == MessagesStatus.loading ||
        state.status == MessagesStatus.loadingMore) {
      _realtimeSyncPending = true;
      return;
    }

    _realtimeSyncInFlight = true;

    try {
      final response = await _fetch(filter: state.filter, page: 1);

      // Inbox is a summary/feed, not a history thread. Realtime invalidation
      // intentionally resets it to authoritative page one, including the
      // current all/unread filter and server unread count.
      emit(
        state.copyWith(
          status: MessagesStatus.ready,
          conversations: response.conversations,
          unreadConversationCount: response.unreadConversationCount,
          page: response.page,
          hasMore: response.hasMore,
          errorMessage: '',
        ),
      );
    } catch (_) {
      // Keep the already rendered inbox. A later realtime event, reconnect, or
      // manual refresh will retry the authoritative REST read.
    } finally {
      _realtimeSyncInFlight = false;
      _drainPendingRealtimeSync();
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

  @override
  Future<void> close() async {
    _realtimeDebounce?.cancel();

    await _messageInvalidationSubscription?.cancel();
    await _connectionStatusSubscription?.cancel();

    await super.close();
  }
}
