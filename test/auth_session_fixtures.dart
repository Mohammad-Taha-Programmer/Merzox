import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shared session fixtures for the authenticated BLoCs.
///
/// Every authenticated bloc resolves its token through `AuthSessionService`,
/// so these helpers install the three stored shapes that contract has to tell
/// apart: a real session, a leftover token with no session, and a session
/// whose token is blank.

/// CASE C — an active session with a usable token.
void useAuthenticatedSession({
  String token = 'real-token',
  bool business = false,
}) {
  SharedPreferences.setMockInitialValues({
    AuthBloc.sessionKey: true,
    AuthBloc.tokenKey: token,
    AuthBloc.userTypeKey: business ? 'business' : 'normal',
  });
}

/// CASE A — a token left behind after logout. It still looks valid, but the
/// session flag is false, so nothing may treat it as authentication.
void useStaleTokenWithoutSession({
  String token = 'leftover-valid-looking-token',
}) {
  SharedPreferences.setMockInitialValues({
    AuthBloc.sessionKey: false,
    AuthBloc.tokenKey: token,
    AuthBloc.userTypeKey: 'normal',
  });
}

/// CASE B — the session flag is set but the stored token is whitespace only.
void useBlankTokenSession({String token = '   '}) {
  SharedPreferences.setMockInitialValues({
    AuthBloc.sessionKey: true,
    AuthBloc.tokenKey: token,
    AuthBloc.userTypeKey: 'normal',
  });
}
