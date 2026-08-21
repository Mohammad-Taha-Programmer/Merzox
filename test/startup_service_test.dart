import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/startup/startup_destination.dart';
import 'package:merzox/core/startup/startup_service.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StartupService startupService;

  setUp(() {
    startupService = StartupService();
  });

  test('opens onboarding when onboarding has not been completed', () async {
    SharedPreferences.setMockInitialValues({'onboarding_completed': false});

    final destination = await startupService.initialize();

    expect(destination, StartupDestination.onboarding);
  });

  test('opens guest home after onboarding without a session', () async {
    SharedPreferences.setMockInitialValues({
      'onboarding_completed': true,
      AuthBloc.sessionKey: false,
    });

    final destination = await startupService.initialize();

    expect(destination, StartupDestination.guestHome);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(AuthBloc.sessionKey), isFalse);
    expect(prefs.getString(AuthBloc.tokenKey), isNull);
  });

  test('opens customer home for an authenticated customer', () async {
    SharedPreferences.setMockInitialValues({
      'onboarding_completed': true,
      AuthBloc.sessionKey: true,
      AuthBloc.tokenKey: 'customer-token',
      AuthBloc.userTypeKey: 'customer',
    });

    final destination = await startupService.initialize();

    expect(destination, StartupDestination.home);
  });

  test('opens business home for an authenticated business', () async {
    SharedPreferences.setMockInitialValues({
      'onboarding_completed': true,
      AuthBloc.sessionKey: true,
      AuthBloc.tokenKey: 'business-token',
      AuthBloc.userTypeKey: 'business',
    });

    final destination = await startupService.initialize();

    expect(destination, StartupDestination.businessHome);
  });

  test('opens guest home when login is set but token is missing', () async {
    SharedPreferences.setMockInitialValues({
      'onboarding_completed': true,
      AuthBloc.sessionKey: true,
      AuthBloc.userTypeKey: 'customer',
    });

    final destination = await startupService.initialize();

    expect(destination, StartupDestination.guestHome);
  });

  test('opens guest home when login is set but token is empty', () async {
    SharedPreferences.setMockInitialValues({
      'onboarding_completed': true,
      AuthBloc.sessionKey: true,
      AuthBloc.tokenKey: '   ',
      AuthBloc.userTypeKey: 'business',
    });

    final destination = await startupService.initialize();

    expect(destination, StartupDestination.guestHome);
  });
}
