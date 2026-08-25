import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/features/notification_preferences/bloc/notification_preference_bloc.dart';
import 'package:merzox/features/notification_preferences/bloc/notification_preference_event.dart';
import 'package:merzox/features/notification_preferences/widgets/notification_preference_control.dart';
import 'package:merzox/services/notification_preference_service.dart';

import 'localization_test_harness.dart';

class _WidgetGateway implements NotificationPreferenceGateway {
  NotificationPreferenceSnapshot loadResult =
      const NotificationPreferenceSnapshot(productOffers: false);

  Object? loadError;

  Future<NotificationPreferenceSnapshot> Function()? loadHandler;
  Future<NotificationPreferenceSnapshot> Function(bool value)? updateHandler;

  int loadCalls = 0;
  int updateCalls = 0;

  @override
  Future<NotificationPreferenceSnapshot> load({required String token}) async {
    loadCalls += 1;

    if (loadError != null) throw loadError!;

    final handler = loadHandler;
    if (handler != null) {
      return handler();
    }

    return loadResult;
  }

  @override
  Future<NotificationPreferenceSnapshot> update({
    required String token,
    required bool productOffers,
  }) async {
    updateCalls += 1;

    final handler = updateHandler;
    if (handler != null) {
      return handler(productOffers);
    }

    return NotificationPreferenceSnapshot(productOffers: productOffers);
  }
}

Future<AuthSessionSnapshot> _session() async {
  return const AuthSessionSnapshot(
    type: AuthSessionType.customer,
    token: 'widget-token',
  );
}

Widget _app(NotificationPreferenceBloc bloc) {
  return MaterialApp(
    home: Scaffold(
      body: BlocProvider.value(
        value: bloc,
        child: const NotificationPreferenceControl(),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations(languageCode: 'ar');
  });

  testWidgets('initial loading never invents an enabled switch', (
    tester,
  ) async {
    final completer = Completer<NotificationPreferenceSnapshot>();

    final gateway = _WidgetGateway()..loadHandler = () => completer.future;

    final bloc = NotificationPreferenceBloc(
      gateway: gateway,
      sessionReader: _session,
    );
    addTearDown(bloc.close);

    await tester.pumpWidget(_app(bloc));

    bloc.add(const NotificationPreferenceStarted());
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(Switch), findsNothing);

    completer.complete(
      const NotificationPreferenceSnapshot(productOffers: false),
    );

    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('failed initial load shows retry instead of a fake switch', (
    tester,
  ) async {
    final gateway = _WidgetGateway()..loadError = StateError('offline');

    final bloc = NotificationPreferenceBloc(
      gateway: gateway,
      sessionReader: _session,
    );
    addTearDown(bloc.close);

    await tester.pumpWidget(_app(bloc));

    bloc.add(const NotificationPreferenceStarted());
    await tester.pumpAndSettle();

    expect(find.text('إعادة المحاولة'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('server false is rendered as false', (tester) async {
    final gateway = _WidgetGateway()
      ..loadResult = const NotificationPreferenceSnapshot(productOffers: false);

    final bloc = NotificationPreferenceBloc(
      gateway: gateway,
      sessionReader: _session,
    );
    addTearDown(bloc.close);

    await tester.pumpWidget(_app(bloc));

    bloc.add(const NotificationPreferenceStarted());
    await tester.pumpAndSettle();

    final toggle = tester.widget<Switch>(find.byType(Switch));

    expect(toggle.value, isFalse);
    expect(gateway.loadCalls, 1);
  });

  testWidgets('switch keeps confirmed value until PATCH succeeds', (
    tester,
  ) async {
    final completer = Completer<NotificationPreferenceSnapshot>();
    final updateStarted = Completer<void>();

    final gateway = _WidgetGateway()
      ..loadResult = const NotificationPreferenceSnapshot(productOffers: true)
      ..updateHandler = (_) {
        if (!updateStarted.isCompleted) {
          updateStarted.complete();
        }

        return completer.future;
      };

    final bloc = NotificationPreferenceBloc(
      gateway: gateway,
      sessionReader: _session,
    );
    addTearDown(bloc.close);

    await tester.pumpWidget(_app(bloc));

    bloc.add(const NotificationPreferenceStarted());
    await tester.pumpAndSettle();

    var toggle = tester.widget<Switch>(find.byType(Switch));
    expect(toggle.value, isTrue);

    toggle.onChanged!(false);

    await updateStarted.future;
    await tester.pump();

    toggle = tester.widget<Switch>(find.byType(Switch));

    expect(toggle.value, isTrue);
    expect(toggle.onChanged, isNull);
    expect(gateway.updateCalls, 1);

    completer.complete(
      const NotificationPreferenceSnapshot(productOffers: false),
    );

    await tester.pumpAndSettle();

    toggle = tester.widget<Switch>(find.byType(Switch));

    expect(toggle.value, isFalse);
    expect(toggle.onChanged, isNotNull);
  });
}
