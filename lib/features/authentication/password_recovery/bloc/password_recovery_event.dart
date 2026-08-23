sealed class PasswordRecoveryEvent {
  const PasswordRecoveryEvent();
}

final class ForgotPasswordSubmitted extends PasswordRecoveryEvent {
  final String email;

  const ForgotPasswordSubmitted({required this.email});
}

final class ResetPasswordSubmitted extends PasswordRecoveryEvent {
  final String token;
  final String newPassword;

  const ResetPasswordSubmitted({
    required this.token,
    required this.newPassword,
  });
}
