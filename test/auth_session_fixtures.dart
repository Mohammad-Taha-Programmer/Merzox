import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:merzox/core/auth/secure_token_store.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shared session fixtures for the authenticated BLoCs.
///
/// Every authenticated bloc resolves its token through `AuthSessionService`,
/// so these helpers install the three stored shapes that contract has to tell
/// apart: a real session, a leftover token with no session, and a session
/// whose token is blank.
///
/// The session flag lives in preferences and the token lives in secure
/// storage, so each shape has to be installed in both places.

/// CASE C — an active session with a usable token.
void useAuthenticatedSession({
  String token = 'real-token',
  bool business = false,
}) {
  SharedPreferences.setMockInitialValues({
    AuthBloc.sessionKey: true,
    AuthBloc.userTypeKey: business ? 'business' : 'normal',
  });
  FlutterSecureStorage.setMockInitialValues({SecureTokenStore.key: token});
}

/// CASE A — a token left behind after logout. It still looks valid, but the
/// session flag is false, so nothing may treat it as authentication.
void useStaleTokenWithoutSession({
  String token = 'leftover-valid-looking-token',
}) {
  SharedPreferences.setMockInitialValues({
    AuthBloc.sessionKey: false,
    AuthBloc.userTypeKey: 'normal',
  });
  FlutterSecureStorage.setMockInitialValues({SecureTokenStore.key: token});
}

/// CASE B — the session flag is set but the stored token is whitespace only.
void useBlankTokenSession({String token = '   '}) {
  SharedPreferences.setMockInitialValues({
    AuthBloc.sessionKey: true,
    AuthBloc.userTypeKey: 'normal',
  });
  FlutterSecureStorage.setMockInitialValues({SecureTokenStore.key: token});
}
