import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/password_recovery_api_service.dart';
import 'password_recovery_event.dart';
import 'password_recovery_state.dart';

final class PasswordRecoveryBloc
    extends Bloc<PasswordRecoveryEvent, PasswordRecoveryState> {
  final PasswordRecoveryGateway _gateway;

  PasswordRecoveryBloc({PasswordRecoveryGateway? gateway})
    : _gateway = gateway ?? PasswordRecoveryApiService(),
      super(const PasswordRecoveryState()) {
    on<ForgotPasswordSubmitted>(_onForgotPasswordSubmitted);
    on<ResetPasswordSubmitted>(_onResetPasswordSubmitted);
  }

  Future<void> _onForgotPasswordSubmitted(
    ForgotPasswordSubmitted event,
    Emitter<PasswordRecoveryState> emit,
  ) async {
    emit(const PasswordRecoveryState(status: PasswordRecoveryStatus.loading));

    try {
      await _gateway.requestPasswordReset(
        email: event.email.trim().toLowerCase(),
      );

      emit(
        const PasswordRecoveryState(
          status: PasswordRecoveryStatus.requestAccepted,
        ),
      );
    } catch (error) {
      emit(
        PasswordRecoveryState(
          status: PasswordRecoveryStatus.failure,
          errorMessage: PasswordRecoveryApiService.messageFromError(error),
        ),
      );
    }
  }

  Future<void> _onResetPasswordSubmitted(
    ResetPasswordSubmitted event,
    Emitter<PasswordRecoveryState> emit,
  ) async {
    emit(const PasswordRecoveryState(status: PasswordRecoveryStatus.loading));

    try {
      await _gateway.resetPassword(
        token: event.token.trim(),
        newPassword: event.newPassword,
      );

      emit(
        const PasswordRecoveryState(
          status: PasswordRecoveryStatus.resetSucceeded,
        ),
      );
    } catch (error) {
      emit(
        PasswordRecoveryState(
          status: PasswordRecoveryStatus.failure,
          errorMessage: PasswordRecoveryApiService.messageFromError(error),
        ),
      );
    }
  }
}
