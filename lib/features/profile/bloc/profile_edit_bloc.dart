import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_edit_event.dart';
import 'profile_edit_state.dart';

class ProfileEditBloc extends Bloc<ProfileEditEvent, ProfileEditState> {
  final ApiService _apiService;

  ProfileEditBloc({ApiService? apiService})
    : _apiService = apiService ?? ApiService(),
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

  Future<String> _token() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(AuthBloc.tokenKey);

    if (token == null || token.isEmpty) {
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
