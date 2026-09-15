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

Future<void> _pump(WidgetTester tester) async {
  final BusinessEnrollmentBloc bloc = BusinessEnrollmentBloc();
  addTearDown(bloc.close);

  await pumpLocalized(
    tester,
    BlocProvider<BusinessEnrollmentBloc>.value(
      value: bloc,
      child: BusinessEnrollmentPage(onCompleted: () {}),
    ),
  );
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

  // The second step is the one with a way back, and it is the artboard's
  // chevron like every other board's.
  testWidgets('the way back is the chevron, not Material\'s arrow', (
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
}
