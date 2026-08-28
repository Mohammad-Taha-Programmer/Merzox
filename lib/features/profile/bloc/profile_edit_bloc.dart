import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_edit_event.dart';
import 'profile_edit_state.dart';

class ProfileEditBloc extends Bloc<ProfileEditEvent, ProfileEditState> {
  final ApiService _apiService;
  final AuthSessionService _authSessionService;

  ProfileEditBloc({
    ApiService? apiService,
    AuthSessionService authSessionService = const AuthSessionService(),
  }) : _apiService = apiService ?? ApiService(),
       _authSessionService = authSessionService,
       super(const ProfileEditState()) {
    on<ProfileEditStarted>(_onStarted);
    on<ProfileEditSubmitted>(_onSubmitted);
  }

  Future<void> _onStarted(
    ProfileEditStarted event,
    Emitter<ProfileEditState> emit,
  ) async {
    emit(state.copyWith(status: ProfileEditStatus.loading));

    try {
      final token = await _token();
      final user = await _apiService.me(token: token);
      await _persistUser(user);
      emit(state.copyWith(status: ProfileEditStatus.ready, user: user));
    } catch (error) {
      emit(
        state.copyWith(
          status: ProfileEditStatus.failure,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  Future<void> _onSubmitted(
    ProfileEditSubmitted event,
    Emitter<ProfileEditState> emit,
  ) async {
    emit(state.copyWith(status: ProfileEditStatus.saving));

    try {
      final token = await _token();
      final user = await _apiService.updateProfile(
        token: token,
        name: event.name,
        gender: event.gender,
        address: event.address,
        birthDate: event.birthDate,
        emails: event.emails,
        phones: event.phones,
      );
      await _persistUser(user);
      emit(state.copyWith(status: ProfileEditStatus.success, user: user));
    } catch (error) {
      emit(
        state.copyWith(
          status: ProfileEditStatus.failure,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  /// Session truth lives in [AuthSessionService]: a stale token left behind
  /// after logout, or a blank one, resolves to unauthenticated here rather
  /// than being re-interpreted per bloc.
  Future<String> _token() async {
    final session = await _authSessionService.read();
    final token = session.token;

    if (token == null) {
      throw StateError('Authentication required');
    }

    return token;
  }

  Future<void> _persistUser(AuthApiUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AuthBloc.userIdKey, user.id);
    await prefs.setString(AuthBloc.nameKey, user.name);
    await prefs.setString(AuthBloc.addressKey, user.address);
    await prefs.setString(AuthBloc.userTypeKey, user.userType);
    await prefs.setString(AuthBloc.emailKey, user.email ?? '');
    await prefs.setString(AuthBloc.phoneKey, user.phone ?? '');
    await prefs.setString(AuthBloc.genderKey, user.gender);
  }
}
