enum PasswordRecoveryStatus {
  initial,
  loading,
  requestAccepted,
  resetSucceeded,
  failure,
}

final class PasswordRecoveryState {
  final PasswordRecoveryStatus status;
  final String? errorMessage;

  const PasswordRecoveryState({
    this.status = PasswordRecoveryStatus.initial,
    this.errorMessage,
  });
}
