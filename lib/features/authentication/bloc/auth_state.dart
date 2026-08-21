final class AuthState {
  final AuthStatus status;
  final bool isGuest;
  final String? errorMessage;
  final String? successMessage;
  final String? userType;

  const AuthState({
    this.status = AuthStatus.initial,
    this.isGuest = false,
    this.errorMessage,
    this.successMessage,
    this.userType,
  });

  AuthState copyWith({
    AuthStatus? status,
    bool? isGuest,
    String? errorMessage,
    String? successMessage,
    String? userType,
  }) {
    return AuthState(
      status: status ?? this.status,
      isGuest: isGuest ?? this.isGuest,
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
  guest,
  unauthenticated,
  failure,
}
