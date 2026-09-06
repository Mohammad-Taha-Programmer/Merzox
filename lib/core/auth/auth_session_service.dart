import 'package:shared_preferences/shared_preferences.dart';

import 'role_switch_service.dart';
import 'secure_token_store.dart';

import '../../features/authentication/bloc/auth_bloc.dart';

enum AuthSessionType { unauthenticated, customer, business }

final class AuthSessionSnapshot {
  /// Which side of the app this session is on right now.
  ///
  /// A shop owner may be on the customer side; that is the point of the
  /// switch. Everything that routes should read this.
  final AuthSessionType type;

  /// Whether the account owns a shop at all.
  ///
  /// What the account IS, as opposed to how it is being used. Only enrolling
  /// changes it, and it is the gate on taking the merchant side.
  final bool ownsBusiness;

  final String? token;

  const AuthSessionSnapshot({
    required this.type,
    this.ownsBusiness = false,
    this.token,
  });

  bool get isAuthenticated => type != AuthSessionType.unauthenticated;

  bool get isBusiness => type == AuthSessionType.business;
}

class AuthSessionService {
  final SecureTokenStore _tokens;

  const AuthSessionService({SecureTokenStore tokens = const SecureTokenStore()})
    : _tokens = tokens;

  /// Reads the session for authenticated work during the current app run.
  ///
  /// An unremembered login is intentionally valid here until the process is
  /// restarted. The Remember Me choice controls cold-start restoration, not
  /// whether the freshly authenticated user may use protected features now.
  Future<AuthSessionSnapshot> read() async {
    final prefs = await SharedPreferences.getInstance();
    return _readFromPreferences(prefs, await _tokens.read());
  }

  /// Resolves only a session that is allowed to survive a cold start.
  ///
  /// Existing sessions created before the Remember Me marker existed have no
  /// marker, so a missing value preserves the historical durable behaviour.
  /// An explicit false value is authoritative and the stored authentication
  /// state is purged before startup routing can use it.
  Future<AuthSessionSnapshot> readForStartup() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberSession = prefs.getBool(AuthBloc.rememberSessionKey);

    if (rememberSession == false) {
      await AuthBloc.clearStoredSession();
      return const AuthSessionSnapshot(type: AuthSessionType.unauthenticated);
    }

    return _readFromPreferences(prefs, await _tokens.read());
  }

  /// Reports whether startup is about to purge a still-authenticated
  /// session because Remember Me was explicitly disabled.
  ///
  /// Callers may use this small window to perform authenticated best-effort
  /// cleanup before [readForStartup] removes the stored bearer token.
  Future<bool> hasUnrememberedAuthenticatedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberSession = prefs.getBool(AuthBloc.rememberSessionKey);

    if (rememberSession != false) {
      return false;
    }

    return _readFromPreferences(prefs, await _tokens.read()).isAuthenticated;
  }

  /// The session flag stays in preferences; only the token moved.
  AuthSessionSnapshot _readFromPreferences(
    SharedPreferences prefs,
    String? token,
  ) {
    final sessionActive = prefs.getBool(AuthBloc.sessionKey) ?? false;

    if (!sessionActive || token == null || token.trim().isEmpty) {
      return const AuthSessionSnapshot(type: AuthSessionType.unauthenticated);
    }

    final bool ownsBusiness = accountOwnsBusiness(
      prefs.getString(AuthBloc.userTypeKey),
    );
    final MerzoxRole role = activeRoleFor(
      ownsBusiness: ownsBusiness,
      stored: prefs.getString(AuthBloc.activeRoleKey),
    );

    return AuthSessionSnapshot(
      type: role == MerzoxRole.merchant
          ? AuthSessionType.business
          : AuthSessionType.customer,
      ownsBusiness: ownsBusiness,
      token: token.trim(),
    );
  }
}
