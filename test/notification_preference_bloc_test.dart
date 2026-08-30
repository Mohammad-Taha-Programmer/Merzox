import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/features/notification_preferences/bloc/notification_preference_bloc.dart';
import 'package:merzox/features/notification_preferences/bloc/notification_preference_event.dart';
import 'package:merzox/features/notification_preferences/bloc/notification_preference_state.dart';
import 'package:merzox/services/notification_preference_service.dart';

class _FakeGateway implements NotificationPreferenceGateway {
  NotificationPreferenceSnapshot loadResult =
      const NotificationPreferenceSnapshot(productOffers: true);

  NotificationPreferenceSnapshot updateResult =
      const NotificationPreferenceSnapshot(productOffers: true);

  Object? loadError;
  Object? updateError;

  Future<NotificationPreferenceSnapshot> Function(bool value)? updateHandler;

  int loadCalls = 0;
  int updateCalls = 0;
  bool? requestedValue;
  String? token;

  @override
  Future<NotificationPreferenceSnapshot> load({required String token}) async {
    loadCalls += 1;
    this.token = token;

    if (loadError != null) {
      throw loadError!;
    }

    return loadResult;
  }

  @override
  Future<NotificationPreferenceSnapshot> update({
    required String token,
    required bool value,
    String key = NotificationPreferenceKeys.productOffers,
  }) async {
    updateCalls += 1;
    this.token = token;
    requestedValue = value;

    if (updateError != null) {
      throw updateError!;
    }

    final handler = updateHandler;
    if (handler != null) {
      return handler(value);
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

Future<NotificationPreferenceState> _start(NotificationPreferenceBloc bloc) {
  final result = bloc.stream.firstWhere(
    (state) =>
        state.status == NotificationPreferenceStatus.ready ||
        state.status == NotificationPreferenceStatus.failure,
  );

  bloc.add(const NotificationPreferenceStarted());

  return result;
}

void main() {
  test('initial state comes only from server preference', () async {
    final gateway = _FakeGateway()
      ..loadResult = const NotificationPreferenceSnapshot(productOffers: false);

    final bloc = NotificationPreferenceBloc(
      gateway: gateway,
      sessionReader: _authenticatedSession,
    );
    addTearDown(bloc.close);

    final state = await _start(bloc);

    expect(state.status, NotificationPreferenceStatus.ready);
    expect(state.productOffers, isFalse);
    expect(gateway.loadCalls, 1);
    expect(gateway.token, 'server-session-token');
  });

  test('missing authenticated session fails closed without API call', () async {
    final gateway = _FakeGateway();

    final bloc = NotificationPreferenceBloc(
      gateway: gateway,
      sessionReader: _unauthenticatedSession,
    );
    addTearDown(bloc.close);

    final state = await _start(bloc);

    expect(state.status, NotificationPreferenceStatus.failure);
    expect(state.productOffers, isNull);
    expect(gateway.loadCalls, 0);
  });

  test('requested toggle is not shown before server confirmation', () async {
    final gateway = _FakeGateway();
    final completer = Completer<NotificationPreferenceSnapshot>();
    final updateStarted = Completer<void>();

    gateway.updateHandler = (_) {
      if (!updateStarted.isCompleted) {
        updateStarted.complete();
      }
      return completer.future;
    };

    final bloc = NotificationPreferenceBloc(
      gateway: gateway,
      sessionReader: _authenticatedSession,
    );
    addTearDown(bloc.close);

    await _start(bloc);

    final savingFuture = bloc.stream.firstWhere(
      (state) => state.status == NotificationPreferenceStatus.saving,
    );

    bloc.add(const NotificationPreferenceChanged(false));

    final saving = await savingFuture;

    expect(saving.productOffers, isTrue);

    await updateStarted.future;

    expect(gateway.requestedValue, isFalse);

    final confirmedFuture = bloc.stream.firstWhere(
      (state) =>
          state.status == NotificationPreferenceStatus.ready &&
          state.productOffers == false,
    );

    completer.complete(
      const NotificationPreferenceSnapshot(productOffers: false),
    );

    final confirmed = await confirmedFuture;

    expect(confirmed.productOffers, isFalse);
  });

  test('server response remains authoritative over requested value', () async {
    final gateway = _FakeGateway()
      ..updateResult = const NotificationPreferenceSnapshot(
        productOffers: true,
      );

    final bloc = NotificationPreferenceBloc(
      gateway: gateway,
      sessionReader: _authenticatedSession,
    );
    addTearDown(bloc.close);

    await _start(bloc);

    final result = bloc.stream.firstWhere(
      (state) =>
          state.status == NotificationPreferenceStatus.ready &&
          gateway.updateCalls == 1,
    );

    bloc.add(const NotificationPreferenceChanged(false));

    final state = await result;

    expect(gateway.requestedValue, isFalse);
    expect(state.productOffers, isTrue);
  });

  test('failed save keeps last confirmed server value', () async {
    final gateway = _FakeGateway()..updateError = StateError('offline');

    final bloc = NotificationPreferenceBloc(
      gateway: gateway,
      sessionReader: _authenticatedSession,
    );
    addTearDown(bloc.close);

    await _start(bloc);

    final result = bloc.stream.firstWhere(
      (state) =>
          state.status == NotificationPreferenceStatus.ready &&
          state.errorMessage.isNotEmpty,
    );

    bloc.add(const NotificationPreferenceChanged(false));

    final state = await result;

    expect(state.productOffers, isTrue);
    expect(state.errorMessage, isNotEmpty);
  });

  test('toggle cannot bypass an unresolved preference state', () async {
    final gateway = _FakeGateway();

    final bloc = NotificationPreferenceBloc(
      gateway: gateway,
      sessionReader: _authenticatedSession,
    );
    addTearDown(bloc.close);

    bloc.add(const NotificationPreferenceChanged(false));

    await Future<void>.delayed(Duration.zero);

    expect(gateway.updateCalls, 0);
    expect(bloc.state.productOffers, isNull);
  });
}
