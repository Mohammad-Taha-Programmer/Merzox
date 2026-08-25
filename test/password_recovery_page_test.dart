import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/authentication/password_recovery/bloc/password_recovery_bloc.dart';
import 'package:merzox/features/authentication/password_recovery/data/password_recovery_api_service.dart';
import 'package:merzox/features/authentication/password_recovery/pages/forgot_password_page.dart';
import 'package:merzox/features/authentication/password_recovery/pages/reset_password_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

Future<void> _pumpLocalized(
  WidgetTester tester, {
  required Widget home,
  Locale locale = const Locale('ar'),
}) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('ar')],
        path: 'assets/translations',
        fallbackLocale: const Locale('ar'),
        startLocale: locale,
        saveLocale: false,
        child: Builder(
          builder: (context) {
            return MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: home,
            );
          },
        ),
      ),
    );

    await tester.idle();
    await tester.pump();
  });

  await tester.pumpAndSettle();
}

Future<void> _waitForCondition(
  WidgetTester tester, {
  required bool Function() condition,
  required String description,
}) async {
  await tester.runAsync(() async {
    for (var attempt = 0; attempt < 100; attempt += 1) {
      if (condition()) {
        return;
      }

      await Future<void>.delayed(Duration.zero);
    }

    throw StateError('Timed out waiting for $description.');
  });

  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('forgot-password Arabic page submits email and advances', (
    tester,
  ) async {
    final gateway = _PageRecoveryGateway();
    var advanced = false;

    await _pumpLocalized(
      tester,
      home: BlocProvider(
        create: (_) => PasswordRecoveryBloc(gateway: gateway),
        child: ForgotPasswordPage(
          onRequestAccepted: () {
            advanced = true;
          },
          onBackToLogin: () {},
        ),
      ),
    );

    expect(find.text('استعادة كلمة المرور'), findsOneWidget);
    expect(find.text('إرسال تعليمات الاستعادة'), findsOneWidget);

    expect(
      Directionality.of(tester.element(find.text('إرسال تعليمات الاستعادة'))),
      TextDirection.rtl,
    );

    await tester.enterText(find.byType(TextFormField), 'Owner@Example.COM');

    await tester.tap(find.text('إرسال تعليمات الاستعادة'));

    await _waitForCondition(
      tester,
      condition: () => advanced,
      description: 'forgot-password success callback',
    );

    expect(gateway.email, 'owner@example.com');
    expect(advanced, isTrue);
  });

  testWidgets('forgot-password page renders English and LTR', (tester) async {
    final gateway = _PageRecoveryGateway();

    await _pumpLocalized(
      tester,
      locale: const Locale('en'),
      home: BlocProvider(
        create: (_) => PasswordRecoveryBloc(gateway: gateway),
        child: ForgotPasswordPage(
          onRequestAccepted: () {},
          onBackToLogin: () {},
        ),
      ),
    );

    expect(find.text('Password recovery'), findsOneWidget);
    expect(find.text('Forgot your password?'), findsOneWidget);
    expect(find.text('Email address'), findsOneWidget);
    expect(find.text('Send recovery instructions'), findsOneWidget);
    expect(find.text('Back to login'), findsOneWidget);

    expect(
      Directionality.of(
        tester.element(find.text('Send recovery instructions')),
      ),
      TextDirection.ltr,
    );
  });

  testWidgets('reset page submits exact token and new password in English', (
    tester,
  ) async {
    final gateway = _PageRecoveryGateway();
    var completed = false;

    await _pumpLocalized(
      tester,
      locale: const Locale('en'),
      home: BlocProvider(
        create: (_) => PasswordRecoveryBloc(gateway: gateway),
        child: ResetPasswordPage(
          onResetSucceeded: () {
            completed = true;
          },
          onBackToLogin: () {},
        ),
      ),
    );

    expect(find.text('Set a new password'), findsOneWidget);
    expect(find.text('Recovery code'), findsOneWidget);
    expect(find.text('New password'), findsOneWidget);
    expect(find.text('Confirm password'), findsOneWidget);

    final fields = find.byType(TextFormField);

    await tester.enterText(fields.at(0), 'A' * 43);
    await tester.enterText(fields.at(1), 'new-secret');
    await tester.enterText(fields.at(2), 'new-secret');

    await tester.tap(find.text('Change password'));

    await _waitForCondition(
      tester,
      condition: () => completed,
      description: 'reset-password success callback',
    );

    expect(gateway.token, 'A' * 43);
    expect(gateway.password, 'new-secret');
    expect(completed, isTrue);
  });

  testWidgets('reset page refuses passwords beyond bcrypt byte limit', (
    tester,
  ) async {
    final gateway = _PageRecoveryGateway();

    await _pumpLocalized(
      tester,
      locale: const Locale('en'),
      home: BlocProvider(
        create: (_) => PasswordRecoveryBloc(gateway: gateway),
        child: ResetPasswordPage(onResetSucceeded: () {}, onBackToLogin: () {}),
      ),
    );

    final fields = find.byType(TextFormField);
    final tooLong = 'x' * 73;

    await tester.enterText(fields.at(0), 'A' * 43);
    await tester.enterText(fields.at(1), tooLong);
    await tester.enterText(fields.at(2), tooLong);

    await tester.tap(find.text('Change password'));
    await tester.pump();

    expect(find.text('Password is too long'), findsWidgets);
    expect(gateway.token, isNull);
  });
}
