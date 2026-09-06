import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/core/auth/role_switch_service.dart';
import 'package:merzox/core/auth/secure_token_store.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_session_fixtures.dart';

/// One account, used either way round.
///
/// The rule these tests exist for: a reader may take the customer side of any
/// account, but the merchant side only of an account that owns a shop - and
/// owning one comes from enrolment alone, never from the switch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const service = RoleSwitchService();
  const session = AuthSessionService();

  Future<String?> storedRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AuthBloc.activeRoleKey);
  }

  group('accountOwnsBusiness', () {
    test('only the business account type owns a shop', () {
      expect(accountOwnsBusiness('business'), isTrue);
      expect(accountOwnsBusiness('  business  '), isTrue);
      expect(accountOwnsBusiness('normal'), isFalse);
      expect(accountOwnsBusiness(''), isFalse);
      expect(accountOwnsBusiness(null), isFalse);
    });
  });

  group('activeRoleFor', () {
    test('an account that owns no shop is always a customer', () {
      expect(
        activeRoleFor(ownsBusiness: false, stored: null),
        MerzoxRole.customer,
      );
      // A value left behind, or edited on the device, must not hand out a
      // merchant session to an account that never enrolled.
      expect(
        activeRoleFor(ownsBusiness: false, stored: 'merchant'),
        MerzoxRole.customer,
      );
    });

    test('an owner who has not chosen starts on the merchant side', () {
      expect(
        activeRoleFor(ownsBusiness: true, stored: null),
        MerzoxRole.merchant,
      );
      expect(
        activeRoleFor(ownsBusiness: true, stored: '   '),
        MerzoxRole.merchant,
      );
    });

    test('an owner who chose the customer side keeps it', () {
      expect(
        activeRoleFor(ownsBusiness: true, stored: 'customer'),
        MerzoxRole.customer,
      );
      expect(
        activeRoleFor(ownsBusiness: true, stored: ' customer '),
        MerzoxRole.customer,
      );
      expect(
        activeRoleFor(ownsBusiness: true, stored: 'merchant'),
        MerzoxRole.merchant,
      );
    });
  });

  group('taking the customer side', () {
    test('an owner turns to the customer side and stays signed in', () async {
      useAuthenticatedSession(token: 'owner-token', business: true);

      expect((await session.read()).isBusiness, isTrue);

      await service.actAsCustomer();

      final AuthSessionSnapshot after = await session.read();

      expect(after.type, AuthSessionType.customer);
      expect(after.isBusiness, isFalse);
      // Still the same account, still signed in, and it still owns the shop.
      expect(after.ownsBusiness, isTrue);
      expect(after.token, 'owner-token');
      expect(await storedRole(), 'customer');
    });
  });

  group('taking the merchant side', () {
    test('an owner may turn back, and the session follows', () async {
      useAuthenticatedSession(token: 'owner-token', business: true);

      await service.actAsCustomer();
      expect((await session.read()).isBusiness, isFalse);

      expect(await service.actAsMerchant(), isTrue);

      final AuthSessionSnapshot after = await session.read();

      expect(after.type, AuthSessionType.business);
      expect(after.token, 'owner-token');
      expect(await storedRole(), 'merchant');
    });

    test('a customer who never enrolled is refused, and nothing is written', () async {
      useAuthenticatedSession(token: 'customer-token');

      expect(await service.actAsMerchant(), isFalse);

      // The refusal is the whole point: were this to write the role, the
      // enrolment on the home screen would become optional.
      expect(await storedRole(), isNull);

      final AuthSessionSnapshot after = await session.read();

      expect(after.type, AuthSessionType.customer);
      expect(after.ownsBusiness, isFalse);
    });

    test('a signed-out reader is refused', () async {
      useStaleTokenWithoutSession();

      expect(await service.actAsMerchant(), isFalse);
      expect(await storedRole(), isNull);
    });
  });

  group('the role does not outlive the session', () {
    test('signing out forgets which side was chosen', () async {
      useAuthenticatedSession(token: 'owner-token', business: true);

      await service.actAsCustomer();
      expect(await storedRole(), 'customer');

      await AuthBloc.clearStoredSession();

      expect(await storedRole(), isNull);
    });

    test('an owner signing in again lands on the merchant side', () async {
      useAuthenticatedSession(token: 'owner-token', business: true);

      await service.actAsCustomer();
      await AuthBloc.clearStoredSession();

      // What a fresh login writes back: the session, the account type and the
      // token. Not the role - there is nothing to write, and that absence is
      // what puts an owner back on their own side.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AuthBloc.sessionKey, true);
      await prefs.setString(AuthBloc.userTypeKey, 'business');
      FlutterSecureStorage.setMockInitialValues({
        SecureTokenStore.key: 'owner-token',
      });

      expect((await session.read()).isBusiness, isTrue);
    });
  });
}
