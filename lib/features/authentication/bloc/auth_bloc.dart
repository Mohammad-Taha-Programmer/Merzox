import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  static const String sessionKey = 'auth_session_active';
  static const String rememberSessionKey = 'auth_remember_session';
  static const String _legacyGuestKey = 'auth_guest_session';
  static const String nameKey = 'auth_user_name';
  static const String addressKey = 'auth_user_address';
  static const String userTypeKey = 'auth_user_type';
  static const String emailKey = 'auth_user_email';
  static const String phoneKey = 'auth_user_phone';
  static const String genderKey = 'auth_user_gender';
  static const String tokenKey = 'auth_access_token';
  static const String userIdKey = 'auth_user_id';
  static const String locationPermissionGrantedKey =
      'auth_location_permission_granted';
  static const String locationPromptPendingKey = 'auth_location_prompt_pending';
  static const String locationPromptAskedPrefix = 'auth_location_prompt_asked_';

  final ApiService _apiService;

  AuthBloc({ApiService? apiService})
    : _apiService = apiService ?? ApiService(),
      super(const AuthState()) {
    on<LoginSubmitted>(_onLoginSubmitted);
    on<SignupSubmitted>(_onSignupSubmitted);
    on<LogoutRequested>(_onLogoutRequested);
  }

  Future<void> _onLoginSubmitted(
    LoginSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    emit(state.copyWith(status: AuthStatus.loading));

    if (!_isValidIdentifier(event.identifier)) {
      emit(
        state.copyWith(
          status: AuthStatus.failure,
          errorMessage: 'أدخل بريدًا إلكترونيًا أو رقم هاتف صحيحًا',
        ),
      );
      return;
    }

    if (event.password.trim().length < 6) {
      emit(
        state.copyWith(
          status: AuthStatus.failure,
          errorMessage: 'كلمة المرور يجب أن تكون 6 أحرف على الأقل',
        ),
      );
      return;
    }

    try {
      final auth = await _apiService.login(
        identifier: event.identifier,
        password: event.password,
      );
      if (event.requiredUserType != null &&
          auth.user.userType != event.requiredUserType) {
        emit(
          state.copyWith(
            status: AuthStatus.failure,
            errorMessage: 'هذا الحساب ليس حساب أعمال',
          ),
        );
        return;
      }
      await _persistAuthenticatedSession(auth, rememberMe: event.rememberMe);
      emit(
        state.copyWith(
          status: AuthStatus.authenticated,
          userType: auth.user.userType,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: AuthStatus.failure,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  Future<void> _onSignupSubmitted(
    SignupSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    emit(state.copyWith(status: AuthStatus.loading));

    if (event.name.trim().length < 2) {
      emit(
        state.copyWith(
          status: AuthStatus.failure,
          errorMessage: 'أدخل الاسم بشكل صحيح',
        ),
      );
      return;
    }

    final identifier = event.identifier.trim();
    if (!_isValidIdentifier(identifier)) {
      emit(
        state.copyWith(
          status: AuthStatus.failure,
          errorMessage: 'أدخل بريدًا إلكترونيًا أو رقم هاتف صحيحًا',
        ),
      );
      return;
    }

    if (event.password.trim().length < 6) {
      emit(
        state.copyWith(
          status: AuthStatus.failure,
          errorMessage: 'كلمة المرور يجب أن تكون 6 أحرف على الأقل',
        ),
      );
      return;
    }

    try {
      final isEmail = identifier.contains('@');
      final signup = await _apiService.signup(
        name: event.name.trim(),
        email: isEmail ? identifier : null,
        phone: isEmail ? null : identifier,
        password: event.password,
        address: event.address.trim(),
        userType: event.userType.name,
        gender: event.gender,
      );
      await _clearAuthenticatedSession();
      final message = signup.requiresEmailVerification && signup.emailSent
          ? 'تم إرسال رابط التحقق إلى بريدك الإلكتروني.'
          : signup.requiresEmailVerification
          ? 'تم إنشاء رابط التحقق، لكن إعدادات البريد غير مكتملة على الخادم.'
          : 'تم إنشاء الحساب. سجل الدخول للمتابعة.';
      emit(
        state.copyWith(
          status: AuthStatus.signupCreated,
          successMessage: message,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: AuthStatus.failure,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  Future<void> _onLogoutRequested(
    LogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    await clearStoredSession();
    emit(state.copyWith(status: AuthStatus.unauthenticated));
  }

  Future<void> _clearAuthenticatedSession() async {
    await clearStoredSession();
  }

  static Future<void> clearStoredSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(sessionKey, false);
    await prefs.remove(rememberSessionKey);
    await prefs.remove(_legacyGuestKey);
    await prefs.remove(tokenKey);
    await prefs.remove(userIdKey);
    await prefs.remove(nameKey);
    await prefs.remove(addressKey);
    await prefs.remove(userTypeKey);
    await prefs.remove(emailKey);
    await prefs.remove(phoneKey);
    await prefs.remove(genderKey);
    await prefs.remove(locationPermissionGrantedKey);
    await prefs.remove(locationPromptPendingKey);
  }

  Future<void> _persistAuthenticatedSession(
    AuthApiResponse auth, {
    required bool rememberMe,
  }) async {
    if (auth.token.isEmpty || auth.user.id.isEmpty) {
      throw StateError('Invalid authentication response from server');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyGuestKey);
    await prefs.setBool(rememberSessionKey, rememberMe);
    await prefs.setString(tokenKey, auth.token);
    await prefs.setString(userIdKey, auth.user.id);
    await prefs.setString(nameKey, auth.user.name);
    await prefs.setString(addressKey, auth.user.address);
    await prefs.setString(userTypeKey, auth.user.userType);
    await prefs.setString(emailKey, auth.user.email ?? '');
    await prefs.setString(phoneKey, auth.user.phone ?? '');
    await prefs.setString(genderKey, auth.user.gender);
    await prefs.setBool(
      locationPermissionGrantedKey,
      auth.user.permissions.location,
    );

    final askedKey = '$locationPromptAskedPrefix${auth.user.id}';
    final locationPromptAsked = prefs.getBool(askedKey) ?? false;
    await prefs.setBool(
      locationPromptPendingKey,
      !auth.user.permissions.location && !locationPromptAsked,
    );

    // Publish the session as active only after all of its required data and
    // durability choice have been written.
    await prefs.setBool(sessionKey, true);
  }

  bool _isValidIdentifier(String value) {
    final trimmed = value.trim();
    final emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    final phonePattern = RegExp(r'^\+?[0-9]{7,15}$');

    return emailPattern.hasMatch(trimmed) || phonePattern.hasMatch(trimmed);
  }
}
