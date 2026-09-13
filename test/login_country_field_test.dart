import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/widgets/merzox_icons.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/authentication/pages/login_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'localization_test_harness.dart';

/// How the identifier field is divided, and in what order it reads.
///
/// All of it is geometry, which is the only thing that can tell "the country
/// is on the left" apart from "the country is somewhere on the screen". A page
/// that quietly went back to drawing the country at the Arabic starting edge
/// would pass every test about what the field *contains*.
Future<Rect> _rectOf(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  return tester.getRect(finder);
}

Future<void> _pumpLogin(WidgetTester tester) async {
  final AuthBloc bloc = AuthBloc();
  addTearDown(bloc.close);

  await pumpLocalized(
    tester,
    BlocProvider<AuthBloc>.value(
      value: bloc,
      child: LoginPage(
        onAuthenticated: () {},
        onBrowseAsGuest: () {},
        onSignupRequested: () {},
        onForgotPasswordRequested: () {},
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadAppTranslations();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the country sits in the left half, the number in the right', (
    tester,
  ) async {
    await _pumpLogin(tester);

    final Rect field = await _rectOf(
      tester,
      find.descendant(
        of: find.byKey(const Key('login.identifier')),
        matching: find.byType(TextFormField),
      ),
    );
    final Rect divider = await _rectOf(
      tester,
      find.byKey(const Key('login.countryDivider')),
    );
    final Rect country = await _rectOf(
      tester,
      find.byKey(const Key('login.countryCode')),
    );

    expect(country.left, closeTo(field.left, 1));
    expect(divider.right, lessThan(field.center.dx));
    expect(country.right, closeTo(divider.right, 1));
  });

  testWidgets('the line runs the full height of the box', (tester) async {
    await _pumpLogin(tester);

    final Rect field = await _rectOf(
      tester,
      find.descendant(
        of: find.byKey(const Key('login.identifier')),
        matching: find.byType(TextFormField),
      ),
    );
    final Rect divider = await _rectOf(
      tester,
      find.byKey(const Key('login.countryDivider')),
    );

    expect(divider.width, 1);
    expect(divider.height, field.height);
    expect(divider.top, closeTo(field.top, 0.5));
  });

  testWidgets('the block reads code, flag, chevron - left to right', (
    tester,
  ) async {
    await _pumpLogin(tester);

    final Rect code = await _rectOf(tester, find.text('+970'));
    final Rect flag = await _rectOf(tester, find.text('\u{1F1F5}\u{1F1F8}'));
    final Rect chevron = await _rectOf(
      tester,
      find.byIcon(MerzoxIcons.loginCountryChevron),
    );

    expect(code.center.dx, lessThan(flag.center.dx));
    expect(flag.center.dx, lessThan(chevron.center.dx));
  });

  // The set the designer supplied has no arrow of any kind, so the chevron is
  // this project's own drawing. If it ever falls back to Material's triangle
  // the shape changes completely, and nothing else would say so.
  testWidgets('the chevron is the drawn one, not Material\'s triangle', (
    tester,
  ) async {
    await _pumpLogin(tester);

    expect(find.byIcon(MerzoxIcons.loginCountryChevron), findsOneWidget);
    expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
  });
}
