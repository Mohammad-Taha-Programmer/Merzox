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

/// Records the identifier the login screen actually submits.
///
/// The call is failed deliberately: this fake exists to observe the identifier
/// the page normalized, not to drive a successful session through the
/// realtime/push wiring the authenticated branch performs.
final class _RecordingLoginApiService extends ApiService {
  String? submittedIdentifier;

  @override
  Future<AuthApiResponse> login({
    required String identifier,
    required String password,
  }) async {
    submittedIdentifier = identifier;

    throw StateError('login is observed, never completed, in this test');
  }
}

final class _RecordingSignupApiService extends ApiService {
  String? submittedEmail;
  String? submittedPhone;

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
    submittedEmail = email;
    submittedPhone = phone;

    return const SignupApiResponse(
      requiresEmailVerification: true,
      emailSent: true,
    );
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
    // MERZOX-UI-GOLDEN-I5-I1: the Arabic identifier copy now reads as the XD
    // reference does. It is a display change only - see the email-login
    // regression test below.
    expect(find.text('رقم الجوال'), findsOneWidget);
    expect(find.text('قم بإدخال رقم الجوال'), findsOneWidget);
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

  testWidgets('login still submits an email identifier under the Arabic '
      'mobile-number copy', (tester) async {
    final api = _RecordingLoginApiService();

    await _pumpLocalized(
      tester,
      home: BlocProvider(
        create: (_) => AuthBloc(apiService: api),
        child: LoginPage(
          onAuthenticated: () {},
          onBrowseAsGuest: () {},
          onSignupRequested: () {},
          onForgotPasswordRequested: () {},
        ),
      ),
    );

    // The identifier field is the first of the two on the page.
    await tester.enterText(
      find.byType(TextFormField).first,
      'shopper@example.com',
    );
    await tester.enterText(find.byType(TextFormField).last, 'secret123');
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'تسجيل الدخول'));
    // Pumped frame by frame rather than settled: the loading state renders a
    // CircularProgressIndicator, which never goes idle.
    await tester.pump();
    await tester.pump();

    // The '@' branch must win over the selected +972 dial code: an email is
    // forwarded verbatim, never rewritten into a phone number.
    expect(api.submittedIdentifier, 'shopper@example.com');

    // Drain the failure SnackBar so its auto-dismiss timer does not outlive
    // the test.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
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
    expect(find.text('رقم الجوال'), findsOneWidget);
    expect(find.text('قم بإدخال رقم الجوال'), findsOneWidget);
    expect(find.text('الجنس'), findsOneWidget);
    expect(find.text('أنثى'), findsOneWidget);
    expect(find.text('ذكر'), findsOneWidget);
    expect(find.text('إنشاء الحساب'), findsWidgets);

    expect(
      Directionality.of(tester.element(find.text('الاسم كاملاً'))),
      TextDirection.rtl,
    );
  });

  testWidgets('signup back control uses semantic back navigation', (
    tester,
  ) async {
    var loginRequested = false;

    await _pumpLocalized(
      tester,
      home: BlocProvider(
        create: (_) => AuthBloc(apiService: _RecordingSignupApiService()),
        child: SignupPage(
          onSignupCreated: () {},
          onLoginRequested: () {
            loginRequested = true;
          },
        ),
      ),
    );

    final backControl = find.byIcon(Icons.arrow_back_ios_new_rounded);

    expect(backControl, findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward_ios_rounded), findsNothing);

    await tester.tap(backControl);
    await tester.pump();

    expect(loginRequested, isTrue);
  });

  testWidgets('signup still submits an email identifier under the Arabic '
      'mobile-number copy', (tester) async {
    final api = _RecordingSignupApiService();

    await _pumpLocalized(
      tester,
      home: BlocProvider(
        create: (_) => AuthBloc(apiService: api),
        child: SignupPage(onSignupCreated: () {}, onLoginRequested: () {}),
      ),
    );

    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(3));

    await tester.enterText(fields.at(0), 'Owner');
    await tester.enterText(fields.at(1), 'owner@example.com');
    await tester.enterText(fields.at(2), 'secret123');
    await tester.pump();

    final submitButton = find.widgetWithText(FilledButton, 'إنشاء الحساب');

    await tester.ensureVisible(submitButton);
    await tester.pumpAndSettle();
    await tester.tap(submitButton);
    await tester.pump();
    await tester.pump();

    expect(api.submittedEmail, 'owner@example.com');
    expect(api.submittedPhone, isNull);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
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
