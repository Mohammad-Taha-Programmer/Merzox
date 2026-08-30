import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/services/notification_preference_service.dart';

import 'notification_preference_event.dart';
import 'notification_preference_state.dart';

typedef NotificationPreferenceSessionReader =
    Future<AuthSessionSnapshot> Function();

class NotificationPreferenceBloc
    extends Bloc<NotificationPreferenceEvent, NotificationPreferenceState> {
  final NotificationPreferenceGateway _gateway;
  final NotificationPreferenceSessionReader _sessionReader;

  /// Which preference this bloc controls. One instance drives one switch.
  final String preferenceKey;

  NotificationPreferenceBloc({
    NotificationPreferenceGateway? gateway,
    NotificationPreferenceSessionReader? sessionReader,
    this.preferenceKey = NotificationPreferenceKeys.productOffers,
  }) : _gateway = gateway ?? NotificationPreferenceService(),
       _sessionReader =
           sessionReader ?? (() => const AuthSessionService().read()),
       super(const NotificationPreferenceState()) {
    on<NotificationPreferenceStarted>(_onStarted);
    on<NotificationPreferenceRetryRequested>(_onRetryRequested);
    on<NotificationPreferenceChanged>(_onChanged);
  }

  Future<String> _authenticatedToken() async {
    final session = await _sessionReader();
    final token = session.token?.trim();

    if (!session.isAuthenticated || token == null || token.isEmpty) {
      throw StateError(
        'Authenticated notification preference session required',
      );
    }

    return token;
  }

  Future<void> _onStarted(
    NotificationPreferenceStarted event,
    Emitter<NotificationPreferenceState> emit,
  ) async {
    await _load(emit);
  }

  Future<void> _onRetryRequested(
    NotificationPreferenceRetryRequested event,
    Emitter<NotificationPreferenceState> emit,
  ) async {
    await _load(emit);
  }

  Future<void> _load(Emitter<NotificationPreferenceState> emit) async {
    emit(
      const NotificationPreferenceState(
        status: NotificationPreferenceStatus.loading,
      ),
    );

    try {
      final token = await _authenticatedToken();
      final preference = await _gateway.load(token: token);

      emit(
        NotificationPreferenceState(
          status: NotificationPreferenceStatus.ready,
          productOffers: preference.valueOf(preferenceKey),
        ),
      );
    } catch (_) {
      emit(
        const NotificationPreferenceState(
          status: NotificationPreferenceStatus.failure,
          errorMessage: 'notificationPreferences.loadError',
        ),
      );
    }
  }

  Future<void> _onChanged(
    NotificationPreferenceChanged event,
    Emitter<NotificationPreferenceState> emit,
  ) async {
    if (state.status != NotificationPreferenceStatus.ready ||
        state.productOffers == null ||
        state.productOffers == event.productOffers) {
      return;
    }

    final confirmedValue = state.productOffers!;

    // Keep the last server-confirmed value visible while saving.
    // The requested value is not shown until the server returns it.
    emit(
      NotificationPreferenceState(
        status: NotificationPreferenceStatus.saving,
        productOffers: confirmedValue,
      ),
    );

    try {
      final token = await _authenticatedToken();

      final preference = await _gateway.update(
        token: token,
        key: preferenceKey,
        value: event.productOffers,
      );

      // The returned server value is authoritative, even if it differs
      // from the value the client requested.
      emit(
        NotificationPreferenceState(
          status: NotificationPreferenceStatus.ready,
          productOffers: preference.valueOf(preferenceKey),
        ),
      );
    } catch (_) {
      emit(
        NotificationPreferenceState(
          status: NotificationPreferenceStatus.ready,
          productOffers: confirmedValue,
          errorMessage: 'notificationPreferences.saveError',
        ),
      );
    }
  }
}
