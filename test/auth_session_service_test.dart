import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const service = AuthSessionService();

  test('is unauthenticated without an active session or token', () async {
    SharedPreferences.setMockInitialValues({AuthBloc.sessionKey: false});

    final session = await service.read();

    expect(session.type, AuthSessionType.unauthenticated);
    expect(session.token, isNull);
    expect(session.isAuthenticated, isFalse);
  });

  test('is unauthenticated when a token exists without a session', () async {
    SharedPreferences.setMockInitialValues({
      AuthBloc.sessionKey: false,
      AuthBloc.tokenKey: 'token',
    });

    final session = await service.read();

    expect(session.type, AuthSessionType.unauthenticated);
    expect(session.token, isNull);
  });

  test('is unauthenticated when the active session has no token', () async {
    SharedPreferences.setMockInitialValues({AuthBloc.sessionKey: true});

    final session = await service.read();

    expect(session.type, AuthSessionType.unauthenticated);
  });

  test('is unauthenticated when the active session token is blank', () async {
    SharedPreferences.setMockInitialValues({
      AuthBloc.sessionKey: true,
      AuthBloc.tokenKey: '   ',
    });

    final session = await service.read();

    expect(session.type, AuthSessionType.unauthenticated);
  });

  test('reads a non-business authenticated user as a customer', () async {
    SharedPreferences.setMockInitialValues({
      AuthBloc.sessionKey: true,
      AuthBloc.tokenKey: 'customer-token',
      AuthBloc.userTypeKey: 'normal',
    });

    final session = await service.read();

    expect(session.type, AuthSessionType.customer);
    expect(session.token, 'customer-token');
    expect(session.isAuthenticated, isTrue);
    expect(session.isBusiness, isFalse);
  });

  test('reads an authenticated business session', () async {
    SharedPreferences.setMockInitialValues({
      AuthBloc.sessionKey: true,
      AuthBloc.tokenKey: 'business-token',
      AuthBloc.userTypeKey: 'business',
    });

    final session = await service.read();

    expect(session.type, AuthSessionType.business);
    expect(session.token, 'business-token');
    expect(session.isBusiness, isTrue);
  });

  test('ignores the legacy guest flag for authorization', () async {
    SharedPreferences.setMockInitialValues({
      'auth_guest_session': true,
      AuthBloc.sessionKey: false,
    });

    final session = await service.read();

    expect(session.type, AuthSessionType.unauthenticated);
    expect(session.isAuthenticated, isFalse);
  });
}
