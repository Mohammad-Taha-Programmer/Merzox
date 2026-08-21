import 'package:merzox/services/api_service.dart';

enum ProfileEditStatus { initial, loading, ready, saving, success, failure }

final class ProfileEditState {
  final ProfileEditStatus status;
  final AuthApiUser? user;
  final String? errorMessage;

  const ProfileEditState({
    this.status = ProfileEditStatus.initial,
    this.user,
    this.errorMessage,
  });

  ProfileEditState copyWith({
    ProfileEditStatus? status,
    AuthApiUser? user,
    String? errorMessage,
  }) {
    return ProfileEditState(
      status: status ?? this.status,
      user: user ?? this.user,
      errorMessage: errorMessage,
    );
  }
}
