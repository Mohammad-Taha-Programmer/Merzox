import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/widgets/merzox_icons.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/authentication/pages/login_page.dart';
import 'package:merzox/features/authentication/pages/signup_page.dart';
import 'package:merzox/features/business/enrollment/business_enrollment_bloc.dart';
import 'package:merzox/features/business/enrollment/business_enrollment_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'localization_test_harness.dart';

/// How a phone field is divided, and in what order it reads.
///
/// All three screens that ask for a number are put through the same
/// assertions, because the claim being made is that they are one field drawn
/// three times. Three test files, like the three copies of the widget that
/// used to exist, would let one of them go on passing while the screen it
/// describes drifted.
///
/// All of it is geometry, which is the only thing that can tell "the country
/// is on the left" apart from "the country is somewhere on the screen". A page
/// that quietly went back to drawing the country at the Arabic starting edge
/// would pass every test about what the field *contains*.

/// One screen under test: how to build it, and what its field is keyed.
class _Screen {
  final String name;
  final Widget Function() page;
  final String fieldKey;
  final double fieldHeight;

  const _Screen({
    required this.name,
    required this.page,
    required this.fieldKey,
    required this.fieldHeight,
  });

  Key get country => Key('$fieldKey.countryCode');
  Key get line => Key('$fieldKey.countryDivider');
}

final List<_Screen> _screens = <_Screen>[
  _Screen(
    name: 'signing in',
    fieldKey: 'login',
    fieldHeight: 48,
    page: () => LoginPage(
      onAuthenticated: () {},
      onBrowseAsGuest: () {},
      onSignupRequested: () {},
      onForgotPasswordRequested: () {},
    ),
  ),
  _Screen(
    name: 'creating an account',
    fieldKey: 'signup',
    fieldHeight: 46,
    page: () => SignupPage(onSignupCreated: () {}, onLoginRequested: () {}),
  ),
  _Screen(
    name: 'opening a shop',
    fieldKey: 'businessEnrollment',
    fieldHeight: 56,
    page: () => BlocProvider<BusinessEnrollmentBloc>(
      create: (_) => BusinessEnrollmentBloc(),
      child: BusinessEnrollmentPage(onCompleted: () {}),
    ),
  ),
];

Future<void> _pump(WidgetTester tester, _Screen screen) async {
  final AuthBloc bloc = AuthBloc();
  addTearDown(bloc.close);

  await pumpLocalized(
    tester,
    BlocProvider<AuthBloc>.value(value: bloc, child: screen.page()),
  );
}

Rect _rectOf(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  return tester.getRect(finder);
}

/// The box the number is typed into, which on both screens is the only text
/// field that carries a country.
Rect _fieldOf(WidgetTester tester, _Screen screen) {
  final Rect country = _rectOf(tester, find.byKey(screen.country));
  final Finder fields = find.byType(TextField);

  for (int i = 0; i < fields.evaluate().length; i += 1) {
    final Rect box = tester.getRect(fields.at(i));
    if (box.contains(country.center)) return box;
  }

  throw StateError('no field on this screen holds the country block');
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadAppTranslations();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final _Screen screen in _screens) {
    group(screen.name, () {
      testWidgets('the country sits at the left edge of the box', (
        tester,
      ) async {
        await _pump(tester, screen);

        final Rect field = _fieldOf(tester, screen);
        final Rect country = _rectOf(tester, find.byKey(screen.country));
        final Rect line = _rectOf(tester, find.byKey(screen.line));

        expect(country.left, closeTo(field.left, 1));
        expect(line.right, lessThan(field.center.dx));
        expect(country.right, closeTo(line.right, 1));
      });

      testWidgets('the line runs the full height of the box', (tester) async {
        await _pump(tester, screen);

        final Rect field = _fieldOf(tester, screen);
        final Rect line = _rectOf(tester, find.byKey(screen.line));

        expect(line.width, 1);
        expect(line.height, screen.fieldHeight);
        expect(line.height, closeTo(field.height, 0.5));
        expect(line.top, closeTo(field.top, 0.5));
      });

      testWidgets('the block reads code, flag, chevron - left to right', (
        tester,
      ) async {
        await _pump(tester, screen);

        final Rect code = _rectOf(tester, find.text('+970'));
        final Rect flag = _rectOf(tester, find.text('\u{1F1F5}\u{1F1F8}'));
        final Rect chevron = _rectOf(
          tester,
          find.byIcon(MerzoxIcons.authCountryChevron),
        );

        expect(code.center.dx, lessThan(flag.center.dx));
        expect(flag.center.dx, lessThan(chevron.center.dx));
      });

      // The set the designer supplied has no arrow of any kind, so the chevron
      // is this project's own drawing. If it ever falls back to Material's
      // triangle the shape changes completely, and nothing else would say so.
      testWidgets('the chevron is the drawn one, not Material\'s triangle', (
        tester,
      ) async {
        await _pump(tester, screen);

        expect(find.byIcon(MerzoxIcons.authCountryChevron), findsOneWidget);
        expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
      });
    });
  }
}
