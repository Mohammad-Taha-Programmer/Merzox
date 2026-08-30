import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/features/home/home_screen.dart';
import 'package:merzox/features/home/presentation/bloc/home_bloc.dart';
import 'package:merzox/features/home/presentation/bloc/home_event.dart';
import 'package:merzox/features/notification_preferences/widgets/notification_preference_control.dart';
import 'package:merzox/services/notification_preference_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'localization_test_harness.dart';

class _ProfilePreferenceGateway implements NotificationPreferenceGateway {
  NotificationPreferenceSnapshot loadResult =
      const NotificationPreferenceSnapshot(productOffers: false);

  int loadCalls = 0;
  int updateCalls = 0;

  String? loadToken;
  String? updateToken;
  bool? requestedValue;

  @override
  Future<NotificationPreferenceSnapshot> load({required String token}) async {
    loadCalls += 1;
    loadToken = token;

    return loadResult;
  }

  @override
  Future<NotificationPreferenceSnapshot> update({
    required String token,
    required bool value,
    String key = NotificationPreferenceKeys.productOffers,
  }) async {
    updateCalls += 1;
    updateToken = token;
    requestedValue = value;

    return NotificationPreferenceSnapshot(productOffers: value);
  }
}

Future<AuthSessionSnapshot> _customerSession() async {
  return const AuthSessionSnapshot(
    type: AuthSessionType.customer,
    token: 'profile-integration-token',
  );
}

Future<void> _selectProfile(HomeBloc bloc) async {
  if (bloc.state.selectedTab == 4) return;

  final selected = bloc.stream.firstWhere((state) => state.selectedTab == 4);

  bloc.add(const HomeTabChanged(4));

  await selected;
}

Finder _preferenceSwitch() {
  return find.descendant(
    of: find.byType(NotificationPreferenceControl),
    matching: find.byType(Switch),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('authenticated Profile loads and updates the server preference', (
    tester,
  ) async {
    final gateway = _ProfilePreferenceGateway();

    final homeBloc = HomeBloc();
    addTearDown(homeBloc.close);

    await _selectProfile(homeBloc);

    await pumpLocalized(
      tester,
      BlocProvider.value(
        value: homeBloc,
        child: HomeScreen(
          isGuest: false,
          notificationPreferenceGateway: gateway,
          notificationPreferenceSessionReader: _customerSession,
        ),
      ),
    );

    expect(find.byType(NotificationPreferenceControl), findsOneWidget);

    expect(gateway.loadCalls, 1);
    expect(gateway.loadToken, 'profile-integration-token');

    var toggle = tester.widget<Switch>(_preferenceSwitch());

    // Server false must render as false.
    expect(toggle.value, isFalse);

    toggle.onChanged!(true);

    await settleFrames(tester);

    expect(gateway.updateCalls, 1);
    expect(gateway.updateToken, 'profile-integration-token');
    expect(gateway.requestedValue, isTrue);

    toggle = tester.widget<Switch>(_preferenceSwitch());

    // The visible value changes only after the server
    // confirms the authoritative response.
    expect(toggle.value, isTrue);
  });

  testWidgets('guest Profile never creates notification preference authority', (
    tester,
  ) async {
    final gateway = _ProfilePreferenceGateway();

    final homeBloc = HomeBloc();
    addTearDown(homeBloc.close);

    await _selectProfile(homeBloc);

    await pumpLocalized(
      tester,
      BlocProvider.value(
        value: homeBloc,
        child: HomeScreen(
          isGuest: true,
          notificationPreferenceGateway: gateway,
          notificationPreferenceSessionReader: _customerSession,
        ),
      ),
    );

    expect(find.byType(NotificationPreferenceControl), findsNothing);

    expect(gateway.loadCalls, 0);
    expect(gateway.updateCalls, 0);
  });
}
