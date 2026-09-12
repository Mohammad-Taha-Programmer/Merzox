import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/auth/auth_session_service.dart';
import '../../../services/api_service.dart';
import '../../../services/realtime_service.dart';
import '../notifications_session_store.dart';
import 'notifications_event.dart';
import 'notifications_state.dart';

/// How many the server is asked for at a time.
///
/// Fifty, which is the most it will give: the screen shows fifty before it
/// offers to show more, so asking for twenty meant the first screenful cost
/// three round trips instead of one.
const int kNotificationsFetchSize = 50;

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

  /// What was already fetched in this run of the app, if anything.
  ///
  /// Null means no store: every open pays for a fetch, which is how this
  /// behaved before and is still what a test gets unless it says otherwise.
  final NotificationsSessionStore? _sessionStore;

  NotificationsBloc({
    ApiService? apiService,
    AuthSessionService authSessionService = const AuthSessionService(),
    Stream<RealtimeNotificationInvalidation>? realtimeNotificationInvalidations,
    Stream<RealtimeConnectionStatus>? realtimeConnectionStatuses,
    NotificationsSessionStore? sessionStore,
    this.businessAudience = false,
  }) : _apiService = apiService ?? ApiService(),
       _authSessionService = authSessionService,
       _sessionStore = sessionStore,
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

  /// Keeps the store in step with whatever was just proven.
  ///
  /// Only a settled, ready state. Remembering a failure would hand the next
  /// press of the bell an empty list wearing the face of a loaded one, and the
  /// reader would have to close the app to be shown their notifications again.
  void _remember(NotificationsState settled) {
    if (settled.status != NotificationsStatus.ready) return;

    _sessionStore?.write(
      businessAudience,
      NotificationsSessionSnapshot(
        notifications: settled.notifications,
        unreadCount: settled.unreadCount,
        page: settled.page,
        hasMore: settled.hasMore,
      ),
    );
  }

  /// Opens on what is already known, and asks the server only if nothing is.
  ///
  /// The bell builds a new bloc every time it is pressed, so without this the
  /// second press refetched a list that had not changed and made the reader
  /// watch a spinner to be shown it again. What has arrived since is not
  /// missed: the socket says so, and a realtime sync folds it in.
  Future<void> _onStarted(
    NotificationsStarted event,
    Emitter<NotificationsState> emit,
  ) async {
    final NotificationsSessionSnapshot? held = _sessionStore?.read(
      businessAudience,
    );

    if (held != null) {
      emit(
        state.copyWith(
          status: NotificationsStatus.ready,
          notifications: held.notifications,
          unreadCount: held.unreadCount,
          page: held.page,
          hasMore: held.hasMore,
          errorMessage: '',
        ),
      );

      _remember(state);
      _drainPendingRealtimeSync();
      return;
    }

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
        limit: kNotificationsFetchSize,
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
      _remember(state);
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
        limit: kNotificationsFetchSize,
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
      _remember(state);
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
      _remember(state);
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
      _remember(state);
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
        limit: kNotificationsFetchSize,
      );

      // Page one goes on top of what is already held rather than replacing
      // it. A notification arriving says nothing about the pages a reader has
      // scrolled through, and throwing them away sent somebody who had gone
      // four pages deep back to the top because a message came in.
      //
      // Which page we are on therefore does not reset either: the next `load
      // more` has to ask for the page after the deepest one fetched, not for
      // the second one again. `hasMore` is only the fresh page's answer while
      // page one is all there is - past that, the deepest page is the only one
      // that knows whether the feed has an end.
      final bool deeperThanPageOne = state.page > 1;

      emit(
        state.copyWith(
          status: NotificationsStatus.ready,
          notifications: mergeNotificationPageOne(
            held: state.notifications,
            fresh: response.notifications,
          ),
          unreadCount: response.unreadCount,
          page: deeperThanPageOne ? state.page : response.page,
          hasMore: deeperThanPageOne ? state.hasMore : response.hasMore,
          errorMessage: '',
        ),
      );
    } catch (_) {
      // Keep already-rendered authoritative state. A later event, reconnect,
      // or manual refresh will retry REST truth.
    } finally {
      _realtimeSyncInFlight = false;
      _remember(state);
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
