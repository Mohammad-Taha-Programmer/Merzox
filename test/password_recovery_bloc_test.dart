import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/authentication/password_recovery/bloc/password_recovery_bloc.dart';
import 'package:merzox/features/authentication/password_recovery/bloc/password_recovery_event.dart';
import 'package:merzox/features/authentication/password_recovery/bloc/password_recovery_state.dart';
import 'package:merzox/features/authentication/password_recovery/data/password_recovery_api_service.dart';

final class _FakeRecoveryGateway implements PasswordRecoveryGateway {
  String? requestedEmail;
  String? resetToken;
  String? resetPasswordValue;
  Object? error;

  @override
  Future<void> requestPasswordReset({required String email}) async {
    requestedEmail = email;

    if (error != null) {
      throw error!;
    }
  }

  @override
  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    resetToken = token;
    resetPasswordValue = newPassword;

    if (error != null) {
      throw error!;
    }
  }
}

void main() {
  test('forgot password normalizes email and reaches accepted state', () async {
    final gateway = _FakeRecoveryGateway();
    final bloc = PasswordRecoveryBloc(gateway: gateway);

    final accepted = bloc.stream.firstWhere(
      (state) => state.status == PasswordRecoveryStatus.requestAccepted,
    );

    bloc.add(const ForgotPasswordSubmitted(email: '  Owner@Example.COM  '));

    await accepted;

    expect(gateway.requestedEmail, 'owner@example.com');

    await bloc.close();
  });

  test(
    'reset password forwards token and password without changing password',
    () async {
      final gateway = _FakeRecoveryGateway();
      final bloc = PasswordRecoveryBloc(gateway: gateway);

      final succeeded = bloc.stream.firstWhere(
        (state) => state.status == PasswordRecoveryStatus.resetSucceeded,
      );

      bloc.add(
        ResetPasswordSubmitted(
          token: '  ${'A' * 43}  ',
          newPassword: ' Secret 123 ',
        ),
      );

      await succeeded;

      expect(gateway.resetToken, 'A' * 43);
      expect(gateway.resetPasswordValue, ' Secret 123 ');

      await bloc.close();
    },
  );

  test('gateway failure becomes recovery failure state', () async {
    final gateway = _FakeRecoveryGateway()
      ..error = StateError('backend failure');

    final bloc = PasswordRecoveryBloc(gateway: gateway);

    final failed = bloc.stream.firstWhere(
      (state) => state.status == PasswordRecoveryStatus.failure,
    );

    bloc.add(const ForgotPasswordSubmitted(email: 'owner@example.com'));

    final state = await failed;

    expect(state.errorMessage, isNotEmpty);

    await bloc.close();
  });
}
