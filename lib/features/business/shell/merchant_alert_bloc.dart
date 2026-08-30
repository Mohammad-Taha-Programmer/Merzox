import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/auth/auth_session_service.dart';
import '../../../services/api_service.dart';
import '../../../services/realtime_service.dart';

/// The in-app banner of `الرئيسية – 17`.
///
/// The artboard drops an orange strip across the order table reading "Yasmin
/// Khaled rated the store" — a notification arriving while the merchant is
/// looking at something else. The realtime socket only says that the business
/// audience's notifications changed, so this reads the newest unread one to
/// find out what to say.
///
/// It deliberately does not mark anything read: the banner is a glance, and
/// the notifications screen is where reading happens.
sealed class MerchantAlertEvent {
  const MerchantAlertEvent();
}

final class MerchantAlertStarted extends MerchantAlertEvent {
  const MerchantAlertStarted();
}

/// The socket said this audience's notifications changed.
final class MerchantAlertSyncRequested extends MerchantAlertEvent {
  const MerchantAlertSyncRequested();
}

/// The banner's own timer expired, or the merchant dismissed it.
final class MerchantAlertDismissed extends MerchantAlertEvent {
  const MerchantAlertDismissed();
}

final class MerchantAlertState {
  /// What the banner says, or null when no banner is showing.
  final String? message;

  /// The newest notification this bloc has already seen.
  ///
  /// Held so a reconnect — which replays an invalidation — cannot re-announce
  /// something the merchant was already shown.
  final String? lastSeenId;

  const MerchantAlertState({this.message, this.lastSeenId});

  MerchantAlertState copyWith({
    String? message,
    bool clearMessage = false,
    String? lastSeenId,
  }) => MerchantAlertState(
    message: clearMessage ? null : message ?? this.message,
    lastSeenId: lastSeenId ?? this.lastSeenId,
  );
}

class MerchantAlertBloc extends Bloc<MerchantAlertEvent, MerchantAlertState> {
  final ApiService _apiService;
  final AuthSessionService _authSessionService;

  StreamSubscription<RealtimeNotificationInvalidation>? _invalidations;

  MerchantAlertBloc({
    ApiService? apiService,
    AuthSessionService authSessionService = const AuthSessionService(),
    Stream<RealtimeNotificationInvalidation>? realtimeInvalidations,
  }) : _apiService = apiService ?? ApiService(),
       _authSessionService = authSessionService,
       super(const MerchantAlertState()) {
    on<MerchantAlertStarted>(_onStarted);
    on<MerchantAlertSyncRequested>(_onSyncRequested);
    on<MerchantAlertDismissed>((_, Emitter<MerchantAlertState> emit) {
      emit(state.copyWith(clearMessage: true));
    });

    _invalidations = realtimeInvalidations?.listen((
      RealtimeNotificationInvalidation invalidation,
    ) {
      if (invalidation.audience != 'business' || isClosed) return;
      add(const MerchantAlertSyncRequested());
    });
  }

  /// The first read only records where the merchant already is: opening the
  /// shell must not announce a notification that arrived yesterday.
  Future<void> _onStarted(
    MerchantAlertStarted event,
    Emitter<MerchantAlertState> emit,
  ) async {
    final AppNotificationApiModel? newest = await _newestUnread();
    if (newest == null) return;

    emit(state.copyWith(lastSeenId: newest.id));
  }

  Future<void> _onSyncRequested(
    MerchantAlertSyncRequested event,
    Emitter<MerchantAlertState> emit,
  ) async {
    final AppNotificationApiModel? newest = await _newestUnread();
    if (newest == null || newest.id == state.lastSeenId) return;

    emit(
      state.copyWith(
        message: newest.title.isEmpty ? newest.body : newest.title,
        lastSeenId: newest.id,
      ),
    );
  }

  /// Null on any failure: a banner that cannot be built is simply not shown,
  /// and the notifications screen still holds the truth.
  Future<AppNotificationApiModel?> _newestUnread() async {
    try {
      final session = await _authSessionService.read();
      final String? token = session.token;
      if (token == null) return null;

      final NotificationListApiResponse page = await _apiService.notifications(
        token: token,
        businessAudience: true,
        unreadOnly: true,
        limit: 1,
      );

      return page.notifications.isEmpty ? null : page.notifications.first;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> close() async {
    await _invalidations?.cancel();
    return super.close();
  }
}
