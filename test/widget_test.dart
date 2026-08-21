import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/authentication/pages/login_page.dart';
import 'package:merzox/features/onboarding/bloc/onboarding_bloc.dart';
import 'package:merzox/features/onboarding/view/onboarding_screen.dart';

void main() {
  testWidgets('onboarding renders the first page', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider(
          create: (_) => OnboardingBloc(),
          child: OnboardingScreen(onFinished: () {}),
        ),
      ),
    );

    expect(find.text('أفضل العروض القريبة منك'), findsOneWidget);
    expect(find.text('تخطي'), findsOneWidget);
  });

  testWidgets('login renders auth and guest actions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider(
          create: (_) => AuthBloc(),
          child: LoginPage(
            onAuthenticated: () {},
            onBrowseAsGuest: () {},
            onSignupRequested: () {},
          ),
        ),
      ),
    );

    expect(find.text('تسجيل الدخول'), findsWidgets);
    expect(find.text('المتابعة كضيف'), findsOneWidget);
    expect(find.text('ألا تملك حساب؟'), findsOneWidget);
    expect(find.text('قم بإنشاء حساب'), findsOneWidget);
  });
}
