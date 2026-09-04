import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/localization/language_toggle_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The control that switches the app between Arabic and English.
///
/// It used to be one inline `IconButton` on the profile screen; the home screen
/// now carries the same control, so the locale flip is shared rather than
/// copied. What matters is that the shared copy really changes the locale -
/// a control that renders but does nothing would look identical in a golden.

Locale? _seen;

Future<void> _pump(WidgetTester tester, {required Locale start}) async {
  _seen = null;

  await tester.runAsync(() async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const <Locale>[Locale('en'), Locale('ar')],
        path: 'assets/translations',
        fallbackLocale: const Locale('ar'),
        startLocale: start,
        saveLocale: false,
        child: Builder(
          builder: (BuildContext context) {
            _seen = context.locale;
            return MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: const Scaffold(body: Center(child: LanguageToggleButton())),
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

Future<void> _tap(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.tap(find.byType(LanguageToggleButton));
    await tester.idle();
    await tester.pump();
  });
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('a tap moves Arabic to English', (WidgetTester tester) async {
    await _pump(tester, start: const Locale('ar'));
    expect(_seen?.languageCode, 'ar');

    await _tap(tester);

    expect(_seen?.languageCode, 'en');
  });

  testWidgets('and a tap moves back again', (WidgetTester tester) async {
    await _pump(tester, start: const Locale('en'));
    expect(_seen?.languageCode, 'en');

    await _tap(tester);

    expect(_seen?.languageCode, 'ar');
  });

  testWidgets('its tooltip is named in whichever language is showing', (
    WidgetTester tester,
  ) async {
    await _pump(tester, start: const Locale('ar'));

    final Tooltip arabic = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(arabic.message, 'تغيير اللغة');

    await _tap(tester);

    final Tooltip english = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(english.message, 'Change language');
  });

  test('the two languages the control offers are each other', () {
    expect(
      LanguageToggleButton.nextLocale(const Locale('ar')).languageCode,
      'en',
    );
    expect(
      LanguageToggleButton.nextLocale(const Locale('en')).languageCode,
      'ar',
    );

    // Anything unexpected lands on Arabic, the app's fallback, rather than
    // leaving the reader stranded in a language nothing is written in.
    expect(
      LanguageToggleButton.nextLocale(const Locale('fr')).languageCode,
      'ar',
    );
  });
}
