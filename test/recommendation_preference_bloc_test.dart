import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/features/recommendation_preferences/bloc/recommendation_preference_bloc.dart';
import 'package:merzox/features/recommendation_preferences/bloc/recommendation_preference_event.dart';
import 'package:merzox/features/recommendation_preferences/bloc/recommendation_preference_state.dart';
import 'package:merzox/services/recommendation_preference_service.dart';

class _FakeGateway implements RecommendationPreferenceGateway {
  RecommendationPreferenceSnapshot loadResult =
      const RecommendationPreferenceSnapshot(
        enabled: false,
        status: 'notAsked',
      );

  RecommendationPreferenceSnapshot updateResult =
      const RecommendationPreferenceSnapshot(enabled: false, status: 'denied');

  Object? loadError;
  Object? updateError;

  Future<RecommendationPreferenceSnapshot> Function(bool value)? updateHandler;

  int loadCalls = 0;
  int updateCalls = 0;
  bool? requestedValue;
  String? token;

  @override
  Future<RecommendationPreferenceSnapshot> load({required String token}) async {
    loadCalls += 1;
    this.token = token;

    if (loadError != null) {
      throw loadError!;
    }

    return loadResult;
  }

  @override
  Future<RecommendationPreferenceSnapshot> update({
    required String token,
    required bool enabled,
  }) async {
    updateCalls += 1;
    this.token = token;
    requestedValue = enabled;

    if (updateError != null) {
      throw updateError!;
    }

    final handler = updateHandler;

    if (handler != null) {
      return handler(enabled);
    }

    return updateResult;
  }
}

Future<AuthSessionSnapshot> _authenticatedSession() async {
  return const AuthSessionSnapshot(
    type: AuthSessionType.customer,
    token: 'server-session-token',
  );
}

Future<AuthSessionSnapshot> _unauthenticatedSession() async {
  return const AuthSessionSnapshot(type: AuthSessionType.unauthenticated);
}

Future<RecommendationPreferenceState> _start(
  RecommendationPreferenceBloc bloc,
) {
  final result = bloc.stream.firstWhere(
    (state) =>
        state.status == RecommendationPreferenceStatus.ready ||
        state.status == RecommendationPreferenceStatus.failure,
  );

  bloc.add(const RecommendationPreferenceStarted());

  return result;
}

void main() {
  test(
    'initial state comes only from server-confirmed consent snapshot',
    () async {
      final gateway = _FakeGateway()
        ..loadResult = const RecommendationPreferenceSnapshot(
          enabled: true,
          status: 'granted',
        );

      final bloc = RecommendationPreferenceBloc(
        gateway: gateway,
        sessionReader: _authenticatedSession,
      );

      addTearDown(bloc.close);

      final state = await _start(bloc);

      expect(state.status, RecommendationPreferenceStatus.ready);
      expect(state.enabled, isTrue);
      expect(state.consentStatus, 'granted');
      expect(gateway.loadCalls, 1);
      expect(gateway.token, 'server-session-token');
    },
  );

  test('missing authenticated session fails closed without API call', () async {
    final gateway = _FakeGateway();

    final bloc = RecommendationPreferenceBloc(
      gateway: gateway,
      sessionReader: _unauthenticatedSession,
    );

    addTearDown(bloc.close);

    final state = await _start(bloc);

    expect(state.status, RecommendationPreferenceStatus.failure);
    expect(state.enabled, isNull);
    expect(gateway.loadCalls, 0);
  });

  test(
    'requested toggle is not displayed before server confirmation',
    () async {
      final gateway = _FakeGateway()
        ..loadResult = const RecommendationPreferenceSnapshot(
          enabled: false,
          status: 'denied',
        );

      final completer = Completer<RecommendationPreferenceSnapshot>();

      final updateStarted = Completer<void>();

      gateway.updateHandler = (_) {
        if (!updateStarted.isCompleted) {
          updateStarted.complete();
        }

        return completer.future;
      };

      final bloc = RecommendationPreferenceBloc(
        gateway: gateway,
        sessionReader: _authenticatedSession,
      );

      addTearDown(bloc.close);

      await _start(bloc);

      final savingFuture = bloc.stream.firstWhere(
        (state) => state.status == RecommendationPreferenceStatus.saving,
      );

      bloc.add(const RecommendationPreferenceChanged(true));

      final saving = await savingFuture;

      expect(saving.enabled, isFalse);
      expect(saving.consentStatus, 'denied');

      await updateStarted.future;

      expect(gateway.requestedValue, isTrue);

      final confirmedFuture = bloc.stream.firstWhere(
        (state) =>
            state.status == RecommendationPreferenceStatus.ready &&
            state.enabled == true,
      );

      completer.complete(
        const RecommendationPreferenceSnapshot(
          enabled: true,
          status: 'granted',
        ),
      );

      final confirmed = await confirmedFuture;

      expect(confirmed.enabled, isTrue);
      expect(confirmed.consentStatus, 'granted');
    },
  );

  test('server response stays authoritative over requested value', () async {
    final gateway = _FakeGateway()
      ..loadResult = const RecommendationPreferenceSnapshot(
        enabled: false,
        status: 'denied',
      )
      ..updateResult = const RecommendationPreferenceSnapshot(
        enabled: false,
        status: 'notAsked',
      );

    final bloc = RecommendationPreferenceBloc(
      gateway: gateway,
      sessionReader: _authenticatedSession,
    );

    addTearDown(bloc.close);

    await _start(bloc);

    final result = bloc.stream.firstWhere(
      (state) =>
          state.status == RecommendationPreferenceStatus.ready &&
          gateway.updateCalls == 1,
    );

    bloc.add(const RecommendationPreferenceChanged(true));

    final state = await result;

    expect(gateway.requestedValue, isTrue);
    expect(state.enabled, isFalse);
    expect(state.consentStatus, 'notAsked');
  });

  test('failed save keeps last confirmed value and consent state', () async {
    final gateway = _FakeGateway()
      ..loadResult = const RecommendationPreferenceSnapshot(
        enabled: true,
        status: 'granted',
      )
      ..updateError = StateError('offline');

    final bloc = RecommendationPreferenceBloc(
      gateway: gateway,
      sessionReader: _authenticatedSession,
    );

    addTearDown(bloc.close);

    await _start(bloc);

    final result = bloc.stream.firstWhere(
      (state) =>
          state.status == RecommendationPreferenceStatus.ready &&
          state.errorMessage.isNotEmpty,
    );

    bloc.add(const RecommendationPreferenceChanged(false));

    final state = await result;

    expect(state.enabled, isTrue);
    expect(state.consentStatus, 'granted');
  });

  test('toggle cannot bypass unresolved preference state', () async {
    final gateway = _FakeGateway();

    final bloc = RecommendationPreferenceBloc(
      gateway: gateway,
      sessionReader: _authenticatedSession,
    );

    addTearDown(bloc.close);

    bloc.add(const RecommendationPreferenceChanged(true));

    await Future<void>.delayed(Duration.zero);

    expect(gateway.updateCalls, 0);
    expect(bloc.state.enabled, isNull);
  });
}
