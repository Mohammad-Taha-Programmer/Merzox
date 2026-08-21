import 'package:shared_preferences/shared_preferences.dart';

import '../../features/authentication/bloc/auth_bloc.dart';

enum AuthSessionType { unauthenticated, customer, business }

final class AuthSessionSnapshot {
  final AuthSessionType type;
  final String? token;

  const AuthSessionSnapshot({required this.type, this.token});

  bool get isAuthenticated => type != AuthSessionType.unauthenticated;

  bool get isBusiness => type == AuthSessionType.business;
}

class AuthSessionService {
  const AuthSessionService();

  Future<AuthSessionSnapshot> read() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionActive = prefs.getBool(AuthBloc.sessionKey) ?? false;
    final token = prefs.getString(AuthBloc.tokenKey)?.trim();

    if (!sessionActive || token == null || token.isEmpty) {
      return const AuthSessionSnapshot(type: AuthSessionType.unauthenticated);
    }

    final userType = prefs.getString(AuthBloc.userTypeKey);
    return AuthSessionSnapshot(
      type: userType == 'business'
          ? AuthSessionType.business
          : AuthSessionType.customer,
      token: token,
    );
  }
}
