import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/widgets/merzox_back_chevron.dart';
import 'package:merzox/core/widgets/merzox_icons.dart';
import 'package:merzox/core/widgets/merzox_keyboards.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/business/enrollment/business_enrollment_bloc.dart';
import 'package:merzox/features/business/enrollment/business_enrollment_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'localization_test_harness.dart';

/// How the first step of opening a shop treats the person filling it in.
const String _accountNumber = '+970592029316';

/// Pushed onto a route, because the screen is reached by being pushed.
///
/// Not decoration: `AppBar` supplies its own back button when - and only when
/// - the route it sits on can be popped. Pumped as a bare `home:` there is
/// nothing to pop, no button is implied, and a test asking whether Material's
/// arrow is on screen would answer no for a reason that has nothing to do with
/// the screen. That is exactly how the first step kept its Material arrow
/// while a test said it did not.
Future<void> _pump(WidgetTester tester) async {
  final BusinessEnrollmentBloc bloc = BusinessEnrollmentBloc();
  addTearDown(bloc.close);

  await pumpLocalized(
    tester,
    Navigator(
      onGenerateInitialRoutes: (NavigatorState navigator, String _) =>
          <Route<void>>[
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('the screen before')),
            ),
            MaterialPageRoute<void>(
              builder: (_) => BlocProvider<BusinessEnrollmentBloc>.value(
                value: bloc,
                child: BusinessEnrollmentPage(onCompleted: () {}),
              ),
            ),
          ],
    ),
  );
  await settleFrames(tester);
}

/// The field under [label], by the text of its own label.
Finder _fieldLabelled(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(TextFormField));

TextField _fieldAt(WidgetTester tester, String label) =>
    tester.widget<TextField>(
      find.descendant(
        of: _fieldLabelled(label),
        matching: find.byType(TextField),
      ),
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadAppTranslations();
  });

  // The number the reader already signs in with, put in for them. A guess, and
  // one they can clear - which is why it is only a starting value and not a
  // field that refuses to be edited.
  testWidgets('the number field opens on the account\'s own number', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AuthBloc.phoneKey: _accountNumber,
    });

    await _pump(tester);
    await settleFrames(tester);

    expect(_fieldAt(tester, 'رقم الجوال').controller?.text, _accountNumber);
  });

  testWidgets('an account with no stored number leaves the field empty', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await _pump(tester);
    await settleFrames(tester);

    expect(_fieldAt(tester, 'رقم الجوال').controller?.text, '');
  });

  testWidgets('what the reader types is never written over by the guess', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AuthBloc.phoneKey: _accountNumber,
    });

    await _pump(tester);
    await tester.enterText(_fieldLabelled('رقم الجوال'), '+970599000000');
    await settleFrames(tester);

    expect(_fieldAt(tester, 'رقم الجوال').controller?.text, '+970599000000');
  });

  testWidgets('a number asks for the number pad, an address for its own', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await _pump(tester);

    expect(_fieldAt(tester, 'رقم الجوال').keyboardType, kMerzoxPhoneKeyboard);
    expect(
      _fieldAt(tester, 'البريد الإلكتروني').keyboardType,
      kMerzoxEmailKeyboard,
    );
  });

  testWidgets('the password can be looked at', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await _pump(tester);

    const Key eye = ValueKey<String>('businessEnrollment.revealPassword');

    expect(_fieldAt(tester, 'كلمة المرور الحالية').obscureText, isTrue);
    expect(
      find.byIcon(MerzoxIcons.businessEnrollmentShowPassword),
      findsOneWidget,
    );

    await tester.tap(find.byKey(eye));
    await settleFrames(tester);

    expect(_fieldAt(tester, 'كلمة المرور الحالية').obscureText, isFalse);
    expect(
      find.byIcon(MerzoxIcons.businessEnrollmentHidePassword),
      findsOneWidget,
    );
  });

  // Optional at this step. The number above is a way to reach the merchant, and
  // an address can be added later from the shop's own settings.
  testWidgets('no address is not a reason to be stopped', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await _pump(tester);

    await tester.enterText(_fieldLabelled('رقم الجوال'), _accountNumber);
    await tester.enterText(_fieldLabelled('كلمة المرور الحالية'), 'secret-123');
    await tester.tap(find.text('التالي'));
    await settleFrames(tester);

    // The second step is showing, which is what "it was accepted" looks like
    // from here.
    expect(find.text('اسم المتجر'), findsOneWidget);
  });

  testWidgets('a half-typed address is still refused', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await _pump(tester);

    await tester.enterText(_fieldLabelled('رقم الجوال'), _accountNumber);
    await tester.enterText(_fieldLabelled('البريد الإلكتروني'), 'shop@');
    await tester.enterText(_fieldLabelled('كلمة المرور الحالية'), 'secret-123');
    await tester.tap(find.text('التالي'));
    await settleFrames(tester);

    expect(find.text('اسم المتجر'), findsNothing);
  });

  // Both steps, and the first one is the point. It had no `leading` of its own
  // and `AppBar` filled one in - Material's back button - so the mark a reader
  // meets on arriving was the wrong one while the second step had the right
  // one. A test that only pressed on after filling the form never saw it.
  testWidgets('the way back is the chevron on the step you arrive at', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await _pump(tester);

    expect(find.byType(MerzoxBackChevronButton), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(find.byIcon(Icons.arrow_forward), findsNothing);
    expect(find.byIcon(Icons.arrow_forward_ios_rounded), findsNothing);
  });

  testWidgets('the way back is the chevron on the second step too', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await _pump(tester);

    await tester.enterText(_fieldLabelled('رقم الجوال'), _accountNumber);
    await tester.enterText(_fieldLabelled('كلمة المرور الحالية'), 'secret-123');
    await tester.tap(find.text('التالي'));
    await settleFrames(tester);

    expect(find.byType(MerzoxBackChevronButton), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward_ios_rounded), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('businessEnrollment.back')),
    );
    await settleFrames(tester);

    expect(find.text('اسم المتجر'), findsNothing);
  });

  // The two marks the customer's bottom bar draws for the same two things -
  // its profile place and its raised button - rather than a pair Material
  // happened to have.
  testWidgets("the two steps carry the app's own marks", (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await _pump(tester);

    expect(
      find.byIcon(MerzoxIcons.businessEnrollmentAccountStep),
      findsOneWidget,
    );
    expect(
      find.byIcon(MerzoxIcons.businessEnrollmentStoreStep),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.person_outline_rounded), findsNothing);
    expect(find.byIcon(Icons.storefront_outlined), findsNothing);
  });
}
