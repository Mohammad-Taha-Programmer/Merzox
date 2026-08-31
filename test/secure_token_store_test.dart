import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/core/auth/secure_token_store.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The bearer token moved out of `SharedPreferences`.
///
/// It authenticates every request for seven days and only a password reset can
/// revoke it, so it was the one stored value that did not belong in a plain
/// file beside the account's display name. What has to hold after the move:
/// an account signed in before it is not signed out by it, and no copy is left
/// behind in the old place once the new one is written.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const SecureTokenStore store = SecureTokenStore();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  test('a stored token is read back from secure storage', () async {
    await store.write('real-token');

    expect(await store.read(), 'real-token');
  });

  test('nothing stored reads as nothing, not as an empty session', () async {
    expect(await store.read(), isNull);
  });

  test('a blank token is not mistaken for one', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      SecureTokenStore.key: '   ',
    });

    expect(await store.read(), isNull);
  });

  test('clearing removes it', () async {
    await store.write('real-token');
    await store.clear();

    expect(await store.read(), isNull);
  });

  group('the move out of preferences', () {
    test('a token from an older build is migrated on first read', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        SecureTokenStore.legacyPreferencesKey: 'token-from-the-old-build',
      });

      // The account stays signed in across the upgrade.
      expect(await store.read(), 'token-from-the-old-build');

      // And the plaintext copy is gone, which was the whole point.
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(SecureTokenStore.legacyPreferencesKey), isFalse);

      // The second read comes from the new place, with nothing left to move.
      expect(await store.read(), 'token-from-the-old-build');
    });

    test('a secure token wins over a stale preferences copy', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        SecureTokenStore.legacyPreferencesKey: 'stale',
      });
      await store.write('current');

      expect(await store.read(), 'current');
    });

    test('writing erases any copy the old place still held', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        SecureTokenStore.legacyPreferencesKey: 'stale',
      });

      await store.write('current');

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(SecureTokenStore.legacyPreferencesKey), isFalse);
    });

    test('clearing erases it there too', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        SecureTokenStore.legacyPreferencesKey: 'stale',
      });

      await store.clear();

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(SecureTokenStore.legacyPreferencesKey), isFalse);
      expect(await store.read(), isNull);
    });
  });

  group('the session contract still holds', () {
    const AuthSessionService sessions = AuthSessionService();

    test('an active session resolves its token from secure storage', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AuthBloc.sessionKey: true,
        AuthBloc.userTypeKey: 'business',
      });
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        SecureTokenStore.key: 'real-token',
      });

      final AuthSessionSnapshot snapshot = await sessions.read();

      expect(snapshot.isAuthenticated, isTrue);
      expect(snapshot.isBusiness, isTrue);
      expect(snapshot.token, 'real-token');
    });

    test('a token without a session is still not authentication', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AuthBloc.sessionKey: false,
        AuthBloc.userTypeKey: 'normal',
      });
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        SecureTokenStore.key: 'leftover-valid-looking-token',
      });

      final AuthSessionSnapshot snapshot = await sessions.read();

      expect(snapshot.isAuthenticated, isFalse);
      expect(snapshot.token, isNull);
    });

    test('a session with a blank token is not authentication', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AuthBloc.sessionKey: true,
        AuthBloc.userTypeKey: 'normal',
      });
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        SecureTokenStore.key: '   ',
      });

      expect((await sessions.read()).isAuthenticated, isFalse);
    });

    test('clearing the session takes the token with it', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AuthBloc.sessionKey: true,
        AuthBloc.userTypeKey: 'normal',
      });
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        SecureTokenStore.key: 'real-token',
      });

      await AuthBloc.clearStoredSession();

      expect(await store.read(), isNull);
      expect((await sessions.read()).isAuthenticated, isFalse);
    });
  });
}
