import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/auth/auth_session_service.dart';
import '../../../services/api_service.dart';
import '../../../services/realtime_service.dart';
import 'notifications_event.dart';
import 'notifications_state.dart';

class NotificationsBloc extends Bloc<NotificationsEvent, NotificationsState> {
  final ApiService _apiService;
  final AuthSessionService _authSessionService;

  /// A business owner also has a customer inbox, so the audience is chosen by
  /// the screen that opens this bloc rather than inferred from the account.
  final bool businessAudience;

  StreamSubscription<RealtimeNotificationInvalidation>?
  _notificationInvalidationSubscription;

  StreamSubscription<RealtimeConnectionStatus>? _connectionStatusSubscription;

  Timer? _realtimeDebounce;

  /// Guards against a second bulk write while one is still in flight.
  bool _markingAll = false;

  /// Single-row read writes may overlap. Realtime page-one refresh waits until
  /// every optimistic write has either committed or rolled back.
  int _readWritesInFlight = 0;

  bool _realtimeWasDisconnected = false;
  bool _realtimeSyncInFlight = false;
  bool _realtimeSyncPending = false;

  NotificationsBloc({
    ApiService? apiService,
    AuthSessionService authSessionService = const AuthSessionService(),
    Stream<RealtimeNotificationInvalidation>? realtimeNotificationInvalidations,
    Stream<RealtimeConnectionStatus>? realtimeConnectionStatuses,
    this.businessAudience = false,
  }) : _apiService = apiService ?? ApiService(),
       _authSessionService = authSessionService,
       super(const NotificationsState()) {
    on<NotificationsStarted>(_onStarted);
    on<NotificationsRefreshRequested>(_onRefreshRequested);
    on<NotificationsLoadMoreRequested>(_onLoadMoreRequested);
    on<NotificationMarkedRead>(_onMarkedRead);
    on<NotificationsAllMarkedRead>(_onAllMarkedRead);
    on<NotificationsRealtimeSyncRequested>(_onRealtimeSyncRequested);

    _bindRealtime(
      notificationInvalidations: realtimeNotificationInvalidations,
      connectionStatuses: realtimeConnectionStatuses,
    );
  }

  String get _audience => businessAudience ? 'business' : 'customer';

  void _bindRealtime({
    required Stream<RealtimeNotificationInvalidation>?
    notificationInvalidations,
    required Stream<RealtimeConnectionStatus>? connectionStatuses,
  }) {
    _notificationInvalidationSubscription = notificationInvalidations?.listen((
      invalidation,
    ) {
      // A business account can display both customer and business feeds.
      // Only the currently visible audience is invalidated.
      if (invalidation.audience != _audience) {
        return;
      }

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
        add(const NotificationsRealtimeSyncRequested());
      }
    });
  }

  bool get _authoritativeWriteInFlight =>
      _markingAll || _readWritesInFlight > 0;

  void _drainPendingRealtimeSync() {
    if (!_realtimeSyncPending ||
        _realtimeSyncInFlight ||
        _authoritativeWriteInFlight ||
        isClosed) {
      return;
    }

    _realtimeSyncPending = false;
    _scheduleRealtimeSync();
  }

  Future<void> _onStarted(
    NotificationsStarted event,
    Emitter<NotificationsState> emit,
  ) async {
    await _loadFirstPage(emit);
  }

  Future<void> _onRefreshRequested(
    NotificationsRefreshRequested event,
    Emitter<NotificationsState> emit,
  ) async {
    await _loadFirstPage(emit);
  }

  Future<void> _loadFirstPage(Emitter<NotificationsState> emit) async {
    emit(
      state.copyWith(
        status: NotificationsStatus.loading,
        notifications: const [],
        page: 1,
        hasMore: false,
        errorMessage: '',
      ),
    );

    try {
      final response = await _apiService.notifications(
        token: await _token(),
        businessAudience: businessAudience,
      );

      emit(
        state.copyWith(
          status: NotificationsStatus.ready,
          notifications: response.notifications,
          unreadCount: response.unreadCount,
          page: response.page,
          hasMore: response.hasMore,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: NotificationsStatus.failure,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    } finally {
      _drainPendingRealtimeSync();
    }
  }

  Future<void> _onLoadMoreRequested(
    NotificationsLoadMoreRequested event,
    Emitter<NotificationsState> emit,
  ) async {
    if (!state.hasMore || state.status != NotificationsStatus.ready) {
      return;
    }

    emit(state.copyWith(status: NotificationsStatus.loadingMore));

    try {
      final response = await _apiService.notifications(
        token: await _token(),
        businessAudience: businessAudience,
        page: state.page + 1,
      );

      emit(
        state.copyWith(
          status: NotificationsStatus.ready,
          notifications: [...state.notifications, ...response.notifications],
          unreadCount: response.unreadCount,
          page: response.page,
          hasMore: response.hasMore,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: NotificationsStatus.ready,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    } finally {
      _drainPendingRealtimeSync();
    }
  }

  /// Optimistic, but reversible: the row greys out at once, and if the server
  /// refuses the write the exact affected row is put back and the failure is
  /// surfaced. Realtime synchronization is deferred until this write settles.
  Future<void> _onMarkedRead(
    NotificationMarkedRead event,
    Emitter<NotificationsState> emit,
  ) async {
    final target = state.notifications
        .where((notification) => notification.id == event.notificationId)
        .firstOrNull;

    if (target == null || target.isRead) {
      return;
    }

    emit(
      state.copyWith(
        notifications: [
          for (final notification in state.notifications)
            if (notification.id == event.notificationId)
              notification.copyWith(isRead: true)
            else
              notification,
        ],
        unreadCount: state.unreadCount > 0 ? state.unreadCount - 1 : 0,
        errorMessage: '',
      ),
    );

    _readWritesInFlight += 1;

    try {
      await _apiService.markNotificationRead(
        token: await _token(),
        notificationId: event.notificationId,
      );
    } catch (error) {
      emit(
        state.copyWith(
          notifications: [
            for (final notification in state.notifications)
              if (notification.id == event.notificationId)
                notification.copyWith(isRead: false)
              else
                notification,
          ],
          unreadCount: state.unreadCount + 1,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    } finally {
      _readWritesInFlight -= 1;
      _drainPendingRealtimeSync();
    }
  }

  /// The whole visible page is one bulk operation, so the pre-change list and
  /// count are captured and restored together when the server write fails.
  Future<void> _onAllMarkedRead(
    NotificationsAllMarkedRead event,
    Emitter<NotificationsState> emit,
  ) async {
    if (state.unreadCount == 0 || _markingAll) {
      return;
    }

    final previousNotifications = state.notifications;

    final previousUnreadCount = state.unreadCount;

    _markingAll = true;

    emit(
      state.copyWith(
        notifications: [
          for (final notification in state.notifications)
            notification.copyWith(isRead: true),
        ],
        unreadCount: 0,
        errorMessage: '',
      ),
    );

    try {
      await _apiService.markAllNotificationsRead(
        token: await _token(),
        businessAudience: businessAudience,
      );
    } catch (error) {
      emit(
        state.copyWith(
          notifications: previousNotifications,
          unreadCount: previousUnreadCount,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    } finally {
      _markingAll = false;
      _drainPendingRealtimeSync();
    }
  }

  Future<void> _onRealtimeSyncRequested(
    NotificationsRealtimeSyncRequested event,
    Emitter<NotificationsState> emit,
  ) async {
    if (_realtimeSyncInFlight) {
      _realtimeSyncPending = true;
      return;
    }

    if (state.status == NotificationsStatus.loading ||
        state.status == NotificationsStatus.loadingMore ||
        _authoritativeWriteInFlight) {
      _realtimeSyncPending = true;
      return;
    }

    _realtimeSyncInFlight = true;

    try {
      final response = await _apiService.notifications(
        token: await _token(),
        businessAudience: businessAudience,
        page: 1,
      );

      // Notifications are a newest-first feed, not a historical thread.
      // Realtime invalidation intentionally resets pagination to server page 1.
      emit(
        state.copyWith(
          status: NotificationsStatus.ready,
          notifications: response.notifications,
          unreadCount: response.unreadCount,
          page: response.page,
          hasMore: response.hasMore,
          errorMessage: '',
        ),
      );
    } catch (_) {
      // Keep already-rendered authoritative state. A later event, reconnect,
      // or manual refresh will retry REST truth.
    } finally {
      _realtimeSyncInFlight = false;
      _drainPendingRealtimeSync();
    }
  }

  Future<String> _token() async {
    final session = await _authSessionService.read();

    final token = session.token;

    if (token == null) {
      throw StateError('Authentication required');
    }

    if (businessAudience && !session.isBusiness) {
      throw StateError('A business account is required');
    }

    return token;
  }

  @override
  Future<void> close() async {
    _realtimeDebounce?.cancel();

    await _notificationInvalidationSubscription?.cancel();

    await _connectionStatusSubscription?.cancel();

    await super.close();
  }
}
