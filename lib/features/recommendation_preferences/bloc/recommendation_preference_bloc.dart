import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/services/recommendation_preference_service.dart';

import 'recommendation_preference_event.dart';
import 'recommendation_preference_state.dart';

typedef RecommendationPreferenceSessionReader =
    Future<AuthSessionSnapshot> Function();

class RecommendationPreferenceBloc
    extends Bloc<RecommendationPreferenceEvent, RecommendationPreferenceState> {
  final RecommendationPreferenceGateway _gateway;
  final RecommendationPreferenceSessionReader _sessionReader;

  RecommendationPreferenceBloc({
    RecommendationPreferenceGateway? gateway,
    RecommendationPreferenceSessionReader? sessionReader,
  }) : _gateway = gateway ?? RecommendationPreferenceService(),
       _sessionReader =
           sessionReader ?? (() => const AuthSessionService().read()),
       super(const RecommendationPreferenceState()) {
    on<RecommendationPreferenceStarted>(_onStarted);
    on<RecommendationPreferenceRetryRequested>(_onRetryRequested);
    on<RecommendationPreferenceChanged>(_onChanged);
  }

  Future<String> _authenticatedToken() async {
    final session = await _sessionReader();
    final token = session.token?.trim();

    if (!session.isAuthenticated || token == null || token.isEmpty) {
      throw StateError(
        'Authenticated recommendation preference session required',
      );
    }

    return token;
  }

  Future<void> _onStarted(
    RecommendationPreferenceStarted event,
    Emitter<RecommendationPreferenceState> emit,
  ) async {
    await _load(emit);
  }

  Future<void> _onRetryRequested(
    RecommendationPreferenceRetryRequested event,
    Emitter<RecommendationPreferenceState> emit,
  ) async {
    await _load(emit);
  }

  Future<void> _load(Emitter<RecommendationPreferenceState> emit) async {
    emit(
      const RecommendationPreferenceState(
        status: RecommendationPreferenceStatus.loading,
      ),
    );

    try {
      final token = await _authenticatedToken();

      final preference = await _gateway.load(token: token);

      emit(
        RecommendationPreferenceState(
          status: RecommendationPreferenceStatus.ready,
          enabled: preference.enabled,
          consentStatus: preference.status,
        ),
      );
    } catch (_) {
      emit(
        const RecommendationPreferenceState(
          status: RecommendationPreferenceStatus.failure,
          errorMessage: 'recommendationPreferences.loadError',
        ),
      );
    }
  }

  Future<void> _onChanged(
    RecommendationPreferenceChanged event,
    Emitter<RecommendationPreferenceState> emit,
  ) async {
    if (state.status != RecommendationPreferenceStatus.ready ||
        state.enabled == null ||
        state.enabled == event.enabled) {
      return;
    }

    final confirmedValue = state.enabled!;
    final confirmedConsentStatus = state.consentStatus;

    emit(
      RecommendationPreferenceState(
        status: RecommendationPreferenceStatus.saving,
        enabled: confirmedValue,
        consentStatus: confirmedConsentStatus,
      ),
    );

    try {
      final token = await _authenticatedToken();

      final preference = await _gateway.update(
        token: token,
        enabled: event.enabled,
      );

      emit(
        RecommendationPreferenceState(
          status: RecommendationPreferenceStatus.ready,
          enabled: preference.enabled,
          consentStatus: preference.status,
        ),
      );
    } catch (_) {
      emit(
        RecommendationPreferenceState(
          status: RecommendationPreferenceStatus.ready,
          enabled: confirmedValue,
          consentStatus: confirmedConsentStatus,
          errorMessage: 'recommendationPreferences.saveError',
        ),
      );
    }
  }
}
