final class AuthState {
  final AuthStatus status;
  final String? errorMessage;
  final String? successMessage;
  final String? userType;

  const AuthState({
    this.status = AuthStatus.initial,
    this.errorMessage,
    this.successMessage,
    this.userType,
  });

  AuthState copyWith({
    AuthStatus? status,
    String? errorMessage,
    String? successMessage,
    String? userType,
  }) {
    return AuthState(
      status: status ?? this.status,
      errorMessage: errorMessage,
      successMessage: successMessage,
      userType: userType ?? this.userType,
    );
  }
}

enum AuthStatus {
  initial,
  loading,
  signupCreated,
  authenticated,
  unauthenticated,
  failure,
}
