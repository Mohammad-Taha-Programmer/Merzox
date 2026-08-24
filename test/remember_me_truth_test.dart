import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/core/startup/startup_destination.dart';
import 'package:merzox/core/startup/startup_service.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/authentication/bloc/auth_event.dart';
import 'package:merzox/features/authentication/bloc/auth_state.dart';
import 'package:merzox/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SuccessfulLoginApi extends ApiService {
  final String userType;

  _SuccessfulLoginApi({this.userType = 'normal'});

  @override
  Future<AuthApiResponse> login({
    required String identifier,
    required String password,
  }) async {
    return AuthApiResponse(
      token: 'session-token',
      user: AuthApiUser(
        id: 'user-1',
        name: 'Remember User',
        email: 'user@example.com',
        emails: const [],
        phone: null,
        phones: const [],
        address: 'Ramallah',
        userType: userType,
        gender: 'unspecified',
        canChangeName: true,
        canChangeGender: true,
        permissions: const UserPermissions(
          aiPersonalization: false,
          location: false,
          contacts: false,
        ),
      ),
    );
  }
}

Future<AuthState> _performLogin({
  required bool rememberMe,
  String password = 'secret-123',
  String userType = 'normal',
}) async {
  final bloc = AuthBloc(apiService: _SuccessfulLoginApi(userType: userType));

  bloc.add(
    LoginSubmitted(
      identifier: 'user@example.com',
      password: password,
      rememberMe: rememberMe,
      requiredUserType: userType == 'business' ? 'business' : null,
    ),
  );

  final result = await bloc.stream.firstWhere(
    (state) =>
        state.status == AuthStatus.authenticated ||
        state.status == AuthStatus.failure,
  );

  await bloc.close();
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'unchecked login is authenticated now but is purged before cold-start routing',
    () async {
      const password = 'secret-123';

      SharedPreferences.setMockInitialValues({'onboarding_completed': true});

      final loginState = await _performLogin(
        rememberMe: false,
        password: password,
      );

      expect(loginState.status, AuthStatus.authenticated);

      var prefs = await SharedPreferences.getInstance();

      expect(prefs.getBool(AuthBloc.sessionKey), isTrue);
      expect(prefs.getBool(AuthBloc.rememberSessionKey), isFalse);
      expect(prefs.getString(AuthBloc.tokenKey), 'session-token');
      expect(prefs.getString(AuthBloc.userIdKey), 'user-1');

      final currentRunSession = await const AuthSessionService().read();
      expect(currentRunSession.isAuthenticated, isTrue);
      expect(currentRunSession.token, 'session-token');

      for (final key in prefs.getKeys()) {
        expect(
          prefs.get(key),
          isNot(password),
          reason: 'password must never be persisted under $key',
        );
      }

      final startupDestination = await StartupService().initialize();

      expect(startupDestination, StartupDestination.guestHome);

      prefs = await SharedPreferences.getInstance();

      expect(prefs.getBool(AuthBloc.sessionKey), isFalse);
      expect(prefs.getBool(AuthBloc.rememberSessionKey), isNull);
      expect(prefs.getString(AuthBloc.tokenKey), isNull);
      expect(prefs.getString(AuthBloc.userIdKey), isNull);
      expect(prefs.getString(AuthBloc.nameKey), isNull);
      expect(prefs.getString(AuthBloc.addressKey), isNull);
      expect(prefs.getString(AuthBloc.userTypeKey), isNull);
      expect(prefs.getString(AuthBloc.emailKey), isNull);
      expect(prefs.getString(AuthBloc.phoneKey), isNull);
      expect(prefs.getString(AuthBloc.genderKey), isNull);
    },
  );

  test('checked login survives cold-start routing', () async {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});

    final loginState = await _performLogin(rememberMe: true);

    expect(loginState.status, AuthStatus.authenticated);

    final beforeStartup = await SharedPreferences.getInstance();
    expect(beforeStartup.getBool(AuthBloc.sessionKey), isTrue);
    expect(beforeStartup.getBool(AuthBloc.rememberSessionKey), isTrue);
    expect(beforeStartup.getString(AuthBloc.tokenKey), 'session-token');

    final destination = await StartupService().initialize();

    expect(destination, StartupDestination.home);

    final afterStartup = await SharedPreferences.getInstance();
    expect(afterStartup.getBool(AuthBloc.sessionKey), isTrue);
    expect(afterStartup.getBool(AuthBloc.rememberSessionKey), isTrue);
    expect(afterStartup.getString(AuthBloc.tokenKey), 'session-token');
  });

  test('checked business login survives as business startup', () async {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});

    final loginState = await _performLogin(
      rememberMe: true,
      userType: 'business',
    );

    expect(loginState.status, AuthStatus.authenticated);

    final destination = await StartupService().initialize();

    expect(destination, StartupDestination.businessHome);
  });

  test('legacy authenticated session without marker remains durable', () async {
    SharedPreferences.setMockInitialValues({
      'onboarding_completed': true,
      AuthBloc.sessionKey: true,
      AuthBloc.tokenKey: 'legacy-token',
      AuthBloc.userTypeKey: 'normal',
    });

    final destination = await StartupService().initialize();

    expect(destination, StartupDestination.home);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AuthBloc.tokenKey), 'legacy-token');
    expect(prefs.getBool(AuthBloc.rememberSessionKey), isNull);
  });

  test(
    'logout clears remembered durability and authenticated session',
    () async {
      SharedPreferences.setMockInitialValues({'onboarding_completed': true});

      final bloc = AuthBloc(apiService: _SuccessfulLoginApi());

      bloc.add(
        const LoginSubmitted(
          identifier: 'user@example.com',
          password: 'secret-123',
          rememberMe: true,
        ),
      );

      await bloc.stream.firstWhere(
        (state) => state.status == AuthStatus.authenticated,
      );

      bloc.add(const LogoutRequested());

      await bloc.stream.firstWhere(
        (state) => state.status == AuthStatus.unauthenticated,
      );

      await bloc.close();

      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getBool(AuthBloc.sessionKey), isFalse);
      expect(prefs.getBool(AuthBloc.rememberSessionKey), isNull);
      expect(prefs.getString(AuthBloc.tokenKey), isNull);
      expect(prefs.getString(AuthBloc.userIdKey), isNull);
      expect(prefs.getString(AuthBloc.userTypeKey), isNull);
    },
  );
}
