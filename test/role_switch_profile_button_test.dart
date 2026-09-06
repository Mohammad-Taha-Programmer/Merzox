import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/core/auth/role_switch_service.dart';
import 'package:merzox/features/business/shell/business_shell_page.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/home/home_screen.dart';
import 'package:merzox/features/home/presentation/bloc/home_bloc.dart';
import 'package:merzox/features/home/presentation/bloc/home_event.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_session_fixtures.dart';
import 'localization_test_harness.dart';

/// The gate on the customer profile.
///
/// The button there turns the app back to the merchant side. It is offered
/// only to an account that already owns a shop, because enrolment - the card
/// on the home tab - is the only way to own one. A button that appeared for
/// everyone would read as a second way in.
Future<AuthSessionSnapshot> _customerSession() async {
  return const AuthSessionSnapshot(
    type: AuthSessionType.customer,
    token: 'role-switch-token',
  );
}

Future<void> _selectProfile(HomeBloc bloc) async {
  if (bloc.state.selectedTab == 4) return;

  final selected = bloc.stream.firstWhere((state) => state.selectedTab == 4);
  bloc.add(const HomeTabChanged(4));
  await selected;
}

Future<void> _pumpProfile(WidgetTester tester) async {
  final homeBloc = HomeBloc();
  addTearDown(homeBloc.close);

  await _selectProfile(homeBloc);

  await pumpLocalized(
    tester,
    BlocProvider.value(
      value: homeBloc,
      child: HomeScreen(
        isGuest: false,
        notificationPreferenceSessionReader: _customerSession,
        recommendationPreferenceSessionReader: _customerSession,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  Finder merchantButton() => find.widgetWithText(
    FilledButton,
    'التسجيل كتاجر',
  );

  testWidgets('an account that owns a shop is offered the merchant side', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      AuthBloc.sessionKey: true,
      AuthBloc.userTypeKey: 'business',
      AuthBloc.nameKey: 'صاحب المتجر',
    });

    await _pumpProfile(tester);

    expect(merchantButton(), findsOneWidget);
  });

  testWidgets('an account that never enrolled is not offered it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      AuthBloc.sessionKey: true,
      AuthBloc.userTypeKey: 'normal',
      AuthBloc.nameKey: 'زبون',
    });

    await _pumpProfile(tester);

    // Nothing stands in for it either: the way to a shop is the enrolment
    // card on the home tab.
    expect(merchantButton(), findsNothing);
  });

  testWidgets('the merchant side button turns the app to the customer side', (
    tester,
  ) async {
    useAuthenticatedSession(token: 'owner-token', business: true);

    const AuthSessionService session = AuthSessionService();
    expect((await session.read()).isBusiness, isTrue);

    await pumpLocalized(
      tester,
      Scaffold(
        body: Center(
          child: RegisterAsCustomerButton(
            onPressed: () => const RoleSwitchService().actAsCustomer(),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(RegisterAsCustomerButton));
    await settleFrames(tester);

    final AuthSessionSnapshot after = await session.read();

    expect(after.type, AuthSessionType.customer);
    // The same account throughout: still signed in, still the owner of a
    // shop, and so still able to turn back.
    expect(after.token, 'owner-token');
    expect(after.ownsBusiness, isTrue);
  });

  testWidgets('a missing account type is not treated as a shop', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({AuthBloc.sessionKey: true});

    await _pumpProfile(tester);

    expect(merchantButton(), findsNothing);
  });
}
