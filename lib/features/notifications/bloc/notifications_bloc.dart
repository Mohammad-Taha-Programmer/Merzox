import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/api_service.dart';
import '../../authentication/bloc/auth_bloc.dart';
import 'notifications_event.dart';
import 'notifications_state.dart';

class NotificationsBloc extends Bloc<NotificationsEvent, NotificationsState> {
  final ApiService _apiService;

  /// A business owner also has a customer inbox, so the audience is chosen by
  /// the screen that opens this bloc rather than inferred from the account.
  final bool businessAudience;

  NotificationsBloc({ApiService? apiService, this.businessAudience = false})
    : _apiService = apiService ?? ApiService(),
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

  /// The row is greyed out immediately; the server call only confirms it, so a
  /// slow network never leaves the list feeling stuck.
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
      ),
    );

    try {
      await _apiService.markNotificationRead(
        token: await _token(),
        notificationId: event.notificationId,
      );
    } catch (_) {}
  }

  Future<void> _onAllMarkedRead(
    NotificationsAllMarkedRead event,
    Emitter<NotificationsState> emit,
  ) async {
    if (state.unreadCount == 0) return;

    emit(
      state.copyWith(
        notifications: [
          for (final notification in state.notifications)
            notification.copyWith(isRead: true),
        ],
        unreadCount: 0,
      ),
    );

    try {
      await _apiService.markAllNotificationsRead(
        token: await _token(),
        businessAudience: businessAudience,
      );
    } catch (error) {
      emit(state.copyWith(errorMessage: ApiService.messageFromError(error)));
    }
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
