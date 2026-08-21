sealed class AuthEvent {
  const AuthEvent();
}

final class LoginSubmitted extends AuthEvent {
  final String identifier;
  final String password;
  final String? requiredUserType;

  const LoginSubmitted({
    required this.identifier,
    required this.password,
    this.requiredUserType,
  });
}

final class SignupSubmitted extends AuthEvent {
  final String name;
  final String identifier;
  final String password;
  final String address;
  final UserType userType;
  final String gender;

  const SignupSubmitted({
    required this.name,
    required this.identifier,
    required this.password,
    required this.address,
    required this.userType,
    this.gender = 'unspecified',
  });
}

final class LogoutRequested extends AuthEvent {
  const LogoutRequested();
}

enum UserType { normal, business }
