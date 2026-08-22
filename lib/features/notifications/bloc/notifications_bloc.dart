import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/api_service.dart';
import '../../../core/auth/auth_session_service.dart';
import 'notifications_event.dart';
import 'notifications_state.dart';

class NotificationsBloc extends Bloc<NotificationsEvent, NotificationsState> {
  final ApiService _apiService;
  final AuthSessionService _authSessionService;

  /// A business owner also has a customer inbox, so the audience is chosen by
  /// the screen that opens this bloc rather than inferred from the account.
  final bool businessAudience;

  /// Guards against a second bulk write while one is still in flight.
  bool _markingAll = false;

  NotificationsBloc({
    ApiService? apiService,
    AuthSessionService authSessionService = const AuthSessionService(),
    this.businessAudience = false,
  }) : _apiService = apiService ?? ApiService(),
       _authSessionService = authSessionService,
       super(const NotificationsState()) {
    on<NotificationsStarted>(_onStarted);
    on<NotificationsRefreshRequested>(_onRefreshRequested);
    on<NotificationsLoadMoreRequested>(_onLoadMoreRequested);
    on<NotificationMarkedRead>(_onMarkedRead);
    on<NotificationsAllMarkedRead>(_onAllMarkedRead);
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
    }
  }

  Future<void> _onLoadMoreRequested(
    NotificationsLoadMoreRequested event,
    Emitter<NotificationsState> emit,
  ) async {
    if (!state.hasMore || state.status != NotificationsStatus.ready) return;

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
    }
  }

  /// Optimistic, but reversible: the row greys out at once, and if the server
  /// refuses the write the exact affected row is put back and the failure is
  /// surfaced. A silent catch here would leave the UI claiming a read state
  /// MongoDB never recorded.
  Future<void> _onMarkedRead(
    NotificationMarkedRead event,
    Emitter<NotificationsState> emit,
  ) async {
    final target = state.notifications
        .where((notification) => notification.id == event.notificationId)
        .firstOrNull;
    if (target == null || target.isRead) return;

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

    try {
      await _apiService.markNotificationRead(
        token: await _token(),
        notificationId: event.notificationId,
      );
    } catch (error) {
      // Only this row is reverted, so a rollback cannot undo a different
      // notification the user marked while this request was in flight.
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
    }
  }

  /// The whole visible page is one bulk operation, so the pre-change list and
  /// count are captured and restored together when the server write fails.
  Future<void> _onAllMarkedRead(
    NotificationsAllMarkedRead event,
    Emitter<NotificationsState> emit,
  ) async {
    if (state.unreadCount == 0 || _markingAll) return;

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
    }
  }

  Future<String> _token() async {
    final session = await _authSessionService.read();
    final token = session.token;

    if (token == null) {
      throw StateError('Authentication required');
    }

    // The business feed additionally requires the session to actually be a
    // business. The route guard already strips an `audience=business` claim
    // from a customer and the backend answers 403; this is the middle layer,
    // so a bloc constructed with `businessAudience: true` by any other path
    // still cannot issue the request.
    if (businessAudience && !session.isBusiness) {
      throw StateError('A business account is required');
    }

    return token;
  }
}
