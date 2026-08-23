import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/authentication/password_recovery/bloc/password_recovery_bloc.dart';
import 'package:merzox/features/authentication/password_recovery/data/password_recovery_api_service.dart';
import 'package:merzox/features/authentication/password_recovery/pages/forgot_password_page.dart';
import 'package:merzox/features/authentication/password_recovery/pages/reset_password_page.dart';

final class _PageRecoveryGateway implements PasswordRecoveryGateway {
  String? email;
  String? token;
  String? password;

  @override
  Future<void> requestPasswordReset({required String email}) async {
    this.email = email;
  }

  @override
  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    this.token = token;
    password = newPassword;
  }
}

void main() {
  testWidgets('forgot-password page submits email and advances', (
    tester,
  ) async {
    final gateway = _PageRecoveryGateway();
    var advanced = false;

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider(
          create: (_) => PasswordRecoveryBloc(gateway: gateway),
          child: ForgotPasswordPage(
            onRequestAccepted: () {
              advanced = true;
            },
            onBackToLogin: () {},
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField), 'Owner@Example.COM');

    await tester.tap(find.text('إرسال تعليمات الاستعادة'));

    await tester.pumpAndSettle();

    expect(gateway.email, 'owner@example.com');
    expect(advanced, isTrue);
  });

  testWidgets('reset page submits exact token and new password', (
    tester,
  ) async {
    final gateway = _PageRecoveryGateway();
    var completed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider(
          create: (_) => PasswordRecoveryBloc(gateway: gateway),
          child: ResetPasswordPage(
            onResetSucceeded: () {
              completed = true;
            },
            onBackToLogin: () {},
          ),
        ),
      ),
    );

    final fields = find.byType(TextFormField);

    await tester.enterText(fields.at(0), 'A' * 43);
    await tester.enterText(fields.at(1), 'new-secret');
    await tester.enterText(fields.at(2), 'new-secret');

    await tester.tap(find.text('تغيير كلمة المرور'));

    await tester.pumpAndSettle();

    expect(gateway.token, 'A' * 43);
    expect(gateway.password, 'new-secret');
    expect(completed, isTrue);
  });

  testWidgets('reset page refuses passwords beyond bcrypt byte limit', (
    tester,
  ) async {
    final gateway = _PageRecoveryGateway();

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider(
          create: (_) => PasswordRecoveryBloc(gateway: gateway),
          child: ResetPasswordPage(
            onResetSucceeded: () {},
            onBackToLogin: () {},
          ),
        ),
      ),
    );

    final fields = find.byType(TextFormField);
    final tooLong = 'x' * 73;

    await tester.enterText(fields.at(0), 'A' * 43);
    await tester.enterText(fields.at(1), tooLong);
    await tester.enterText(fields.at(2), tooLong);

    await tester.tap(find.text('تغيير كلمة المرور'));

    await tester.pump();

    expect(find.text('كلمة المرور طويلة جداً'), findsWidgets);
    expect(gateway.token, isNull);
  });
}
