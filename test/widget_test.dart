import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/authentication/bloc/auth_event.dart';
import 'package:merzox/features/authentication/bloc/auth_state.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/features/authentication/pages/login_page.dart';
import 'package:merzox/features/authentication/pages/signup_page.dart';
import 'package:merzox/features/onboarding/bloc/onboarding_bloc.dart';
import 'package:merzox/features/onboarding/view/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

    // EasyLocalization's asynchronous delegate load requires
    // one additional rendered frame before translated widgets
    // can be asserted.
    await tester.pump();
  });

  await tester.pumpAndSettle();
}

final class _SignupMessageApiService extends ApiService {
  final SignupApiResponse result;

  _SignupMessageApiService(this.result);

  @override
  Future<SignupApiResponse> signup({
    required String name,
    String? email,
    String? phone,
    required String password,
    required String userType,
    String address = '',
    String gender = 'unspecified',
  }) async {
    return result;
  }
}

Future<AuthState> _dispatchForAuthStatus(
  AuthBloc bloc,
  AuthEvent event,
  AuthStatus expectedStatus,
) {
  final stateFuture = bloc.stream.firstWhere(
    (state) => state.status == expectedStatus,
  );

  bloc.add(event);

  return stateFuture;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('onboarding renders localized Arabic first page', (tester) async {
    await _pumpLocalized(
      tester,
      home: BlocProvider(
        create: (_) => OnboardingBloc(),
        child: OnboardingScreen(onFinished: () {}),
      ),
    );

    expect(find.text('أفضل الخصومات'), findsOneWidget);
    expect(find.text('تخطي'), findsOneWidget);

    expect(
      Directionality.of(tester.element(find.text('أفضل الخصومات'))),
      TextDirection.rtl,
    );
  });

  testWidgets('onboarding renders localized English first page', (
    tester,
  ) async {
    await _pumpLocalized(
      tester,
      locale: const Locale('en'),
      home: BlocProvider(
        create: (_) => OnboardingBloc(),
        child: OnboardingScreen(onFinished: () {}),
      ),
    );

    expect(find.text('Best offers near you'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);

    expect(
      Directionality.of(tester.element(find.text('Best offers near you'))),
      TextDirection.ltr,
    );
  });

  testWidgets('login renders localized Arabic auth and guest actions', (
    tester,
  ) async {
    var forgotPasswordRequested = false;

    await _pumpLocalized(
      tester,
      home: BlocProvider(
        create: (_) => AuthBloc(),
        child: LoginPage(
          onAuthenticated: () {},
          onBrowseAsGuest: () {},
          onSignupRequested: () {},
          onForgotPasswordRequested: () {
            forgotPasswordRequested = true;
          },
        ),
      ),
    );

    expect(find.text('تسجيل الدخول'), findsWidgets);
    expect(find.text('المتابعة كضيف'), findsOneWidget);
    expect(find.text('ألا تملك حساب؟'), findsOneWidget);
    expect(find.text('قم بإنشاء حساب'), findsOneWidget);
    expect(find.text('نسيت كلمة المرور؟'), findsOneWidget);

    expect(
      Directionality.of(tester.element(find.text('المتابعة كضيف'))),
      TextDirection.rtl,
    );

    await tester.tap(find.text('نسيت كلمة المرور؟'));
    await tester.pump();

    expect(forgotPasswordRequested, isTrue);
  });

  testWidgets('login renders localized English auth and guest actions', (
    tester,
  ) async {
    await _pumpLocalized(
      tester,
      locale: const Locale('en'),
      home: BlocProvider(
        create: (_) => AuthBloc(),
        child: LoginPage(
          onAuthenticated: () {},
          onBrowseAsGuest: () {},
          onSignupRequested: () {},
          onForgotPasswordRequested: () {},
        ),
      ),
    );

    expect(find.text('Login'), findsWidgets);
    expect(find.text('Continue as guest'), findsOneWidget);
    expect(find.text("Don't have an account?"), findsOneWidget);
    expect(find.text('Create an account'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);

    expect(
      Directionality.of(tester.element(find.text('Continue as guest'))),
      TextDirection.ltr,
    );
  });

  testWidgets('signup renders localized English fields and actions', (
    tester,
  ) async {
    await _pumpLocalized(
      tester,
      locale: const Locale('en'),
      home: BlocProvider(
        create: (_) => AuthBloc(),
        child: SignupPage(onSignupCreated: () {}, onLoginRequested: () {}),
      ),
    );

    expect(find.text('Create account'), findsWidgets);
    expect(find.text('Full name'), findsOneWidget);
    expect(find.text('Email or mobile number'), findsOneWidget);
    expect(find.text('Gender'), findsOneWidget);
    expect(find.text('Female'), findsOneWidget);
    expect(find.text('Male'), findsOneWidget);

    expect(
      Directionality.of(tester.element(find.text('Full name'))),
      TextDirection.ltr,
    );
  });

  testWidgets('signup renders localized Arabic fields and RTL', (tester) async {
    await _pumpLocalized(
      tester,
      home: BlocProvider(
        create: (_) => AuthBloc(),
        child: SignupPage(onSignupCreated: () {}, onLoginRequested: () {}),
      ),
    );

    expect(find.text('الاسم كاملاً'), findsOneWidget);
    expect(find.text('الجنس'), findsOneWidget);
    expect(find.text('أنثى'), findsOneWidget);
    expect(find.text('ذكر'), findsOneWidget);
    expect(find.text('إنشاء الحساب'), findsWidgets);

    expect(
      Directionality.of(tester.element(find.text('الاسم كاملاً'))),
      TextDirection.rtl,
    );
  });

  test(
    'auth bloc emits localization keys for local validation failures',
    () async {
      Future<void> verify(AuthEvent event, String expectedKey) async {
        final bloc = AuthBloc();

        final state = await _dispatchForAuthStatus(
          bloc,
          event,
          AuthStatus.failure,
        );

        expect(state.errorMessageKey, expectedKey);
        expect(state.errorMessage, isNull);

        await bloc.close();
      }

      await verify(
        const LoginSubmitted(
          identifier: 'not-an-identifier',
          password: 'secret1',
        ),
        'validation.invalidIdentifier',
      );

      await verify(
        const LoginSubmitted(identifier: 'owner@example.com', password: '123'),
        'validation.passwordMin6',
      );

      await verify(
        const SignupSubmitted(
          name: 'A',
          identifier: 'owner@example.com',
          password: 'secret1',
          address: '',
          userType: UserType.normal,
        ),
        'validation.invalidName',
      );

      await verify(
        const SignupSubmitted(
          name: 'Owner',
          identifier: 'not-an-identifier',
          password: 'secret1',
          address: '',
          userType: UserType.normal,
        ),
        'validation.invalidIdentifier',
      );

      await verify(
        const SignupSubmitted(
          name: 'Owner',
          identifier: 'owner@example.com',
          password: '123',
          address: '',
          userType: UserType.normal,
        ),
        'validation.passwordMin6',
      );
    },
  );

  test('auth bloc emits localization keys for signup outcomes', () async {
    final cases = <({SignupApiResponse result, String key})>[
      (
        result: const SignupApiResponse(
          requiresEmailVerification: true,
          emailSent: true,
        ),
        key: 'auth.signupVerificationEmailSent',
      ),
      (
        result: const SignupApiResponse(
          requiresEmailVerification: true,
          emailSent: false,
        ),
        key: 'auth.signupVerificationEmailUnavailable',
      ),
      (
        result: const SignupApiResponse(
          requiresEmailVerification: false,
          emailSent: false,
        ),
        key: 'auth.signupCreatedLoginPrompt',
      ),
    ];

    for (final testCase in cases) {
      SharedPreferences.setMockInitialValues({});

      final bloc = AuthBloc(
        apiService: _SignupMessageApiService(testCase.result),
      );

      final stateFuture = _dispatchForAuthStatus(
        bloc,
        const SignupSubmitted(
          name: 'Owner',
          identifier: 'owner@example.com',
          password: 'secret1',
          address: '',
          userType: UserType.normal,
        ),
        AuthStatus.signupCreated,
      );

      final state = await stateFuture;

      expect(state.successMessageKey, testCase.key);
      expect(state.successMessage, isNull);

      await bloc.close();
    }
  });
}
