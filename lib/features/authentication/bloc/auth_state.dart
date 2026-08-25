final class AuthState {
  final AuthStatus status;
  final String? errorMessageKey;
  final String? errorMessage;
  final String? successMessageKey;
  final String? successMessage;
  final String? userType;

  const AuthState({
    this.status = AuthStatus.initial,
    this.errorMessageKey,
    this.errorMessage,
    this.successMessageKey,
    this.successMessage,
    this.userType,
  });

  AuthState copyWith({
    AuthStatus? status,
    String? errorMessageKey,
    String? errorMessage,
    String? successMessageKey,
    String? successMessage,
    String? userType,
  }) {
    return AuthState(
      status: status ?? this.status,
      errorMessageKey: errorMessageKey,
      errorMessage: errorMessage,
      successMessageKey: successMessageKey,
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
