import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/auth/auth_session_service.dart';
import '../../../services/api_service.dart';
import '../../../services/realtime_service.dart';
import 'notification_badge_event.dart';
import 'notification_badge_state.dart';

class NotificationBadgeBloc
    extends Bloc<NotificationBadgeEvent, NotificationBadgeState> {
  final ApiService _apiService;
  final AuthSessionService _authSessionService;

  final bool businessAudience;

  StreamSubscription<RealtimeNotificationInvalidation>?
  _notificationInvalidationSubscription;

  StreamSubscription<RealtimeConnectionStatus>? _connectionStatusSubscription;

  Timer? _realtimeDebounce;

  bool _refreshInFlight = false;
  bool _refreshPending = false;
  bool _realtimeWasDisconnected = false;

  NotificationBadgeBloc({
    ApiService? apiService,
    AuthSessionService authSessionService = const AuthSessionService(),
    Stream<RealtimeNotificationInvalidation>? realtimeNotificationInvalidations,
    Stream<RealtimeConnectionStatus>? realtimeConnectionStatuses,
    this.businessAudience = false,
  }) : _apiService = apiService ?? ApiService(),
       _authSessionService = authSessionService,
       super(const NotificationBadgeState()) {
    on<NotificationBadgeStarted>(_onStarted);

    on<NotificationBadgeRealtimeSyncRequested>(_onRealtimeSyncRequested);

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
      if (invalidation.audience != _audience) {
        return;
      }

      _scheduleRefresh();
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
          _scheduleRefresh();
        }
      });
    }
  }

  void _scheduleRefresh() {
    _realtimeDebounce?.cancel();

    _realtimeDebounce = Timer(const Duration(milliseconds: 90), () {
      if (!isClosed) {
        add(const NotificationBadgeRealtimeSyncRequested());
      }
    });
  }

  void _drainPendingRefresh() {
    if (!_refreshPending || _refreshInFlight || isClosed) {
      return;
    }

    _refreshPending = false;
    _scheduleRefresh();
  }

  Future<void> _onStarted(
    NotificationBadgeStarted event,
    Emitter<NotificationBadgeState> emit,
  ) async {
    await _refresh(emit, showLoading: true);
  }

  Future<void> _onRealtimeSyncRequested(
    NotificationBadgeRealtimeSyncRequested event,
    Emitter<NotificationBadgeState> emit,
  ) async {
    if (_refreshInFlight || state.status == NotificationBadgeStatus.loading) {
      _refreshPending = true;
      return;
    }

    await _refresh(emit, showLoading: false);
  }

  Future<void> _refresh(
    Emitter<NotificationBadgeState> emit, {
    required bool showLoading,
  }) async {
    if (_refreshInFlight) {
      _refreshPending = true;
      return;
    }

    _refreshInFlight = true;

    if (showLoading) {
      emit(
        state.copyWith(
          status: NotificationBadgeStatus.loading,
          errorMessage: '',
        ),
      );
    }

    try {
      final unreadCount = await _apiService.notificationUnreadCount(
        token: await _token(),
        businessAudience: businessAudience,
      );

      emit(
        state.copyWith(
          status: NotificationBadgeStatus.ready,
          unreadCount: unreadCount < 0 ? 0 : unreadCount,
          errorMessage: '',
        ),
      );
    } catch (error) {
      // A transient badge refresh failure must not erase a previously proven
      // unread indicator. Keep the last authoritative count and retry on the
      // next socket event/reconnect.
      emit(
        state.copyWith(
          status: NotificationBadgeStatus.failure,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    } finally {
      _refreshInFlight = false;
      _drainPendingRefresh();
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
