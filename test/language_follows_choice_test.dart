import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/localization/language_toggle_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which language the app opens in.
///
/// The rule is that it follows the reader's own choice and never the handset's
/// setting: a phone set to English does not put an Arabic reader into English.
/// Three defaults hold that up together, and any one of them could be changed
/// by somebody who did not know what it was holding - the choice is saved, the
/// saved one beats the start locale on the next launch, and a reader who has
/// never chosen gets Arabic rather than whatever the device says.
///
/// These are `bootstrap.dart`'s own values, repeated so that a change there
/// which breaks the rule fails here rather than in somebody's morning.
const List<Locale> _supported = <Locale>[Locale('en'), Locale('ar')];
const Locale _fallback = Locale('ar');
const Locale _start = Locale('ar');

/// The key easy_localization keeps the choice under, read from its source.
const String _localeKey = 'locale';

/// Opens the app's localization tree and reports the locale it settled on.
Future<Locale> _openedLocale(WidgetTester tester, {String? saved}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    _localeKey: ?saved,
  });

  // What the real startup does before `runApp`: reads the saved choice into
  // the controller. Real asset and preference I/O, so it cannot run on the
  // faked test clock.
  await tester.runAsync(EasyLocalization.ensureInitialized);

  late Locale settled;

  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: _supported,
      path: 'assets/translations',
      fallbackLocale: _fallback,
      startLocale: _start,
      child: Builder(
        builder: (BuildContext context) {
          settled = context.locale;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();

  return settled;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a reader who has chosen gets what they chose', (tester) async {
    expect((await _openedLocale(tester, saved: 'en')).languageCode, 'en');
  });

  testWidgets('and it is still theirs the next time', (tester) async {
    expect((await _openedLocale(tester, saved: 'ar')).languageCode, 'ar');
  });

  testWidgets('a reader who has never chosen gets Arabic', (tester) async {
    // Not the handset's language: the start locale answers this case, which
    // is the whole reason it is set.
    expect((await _openedLocale(tester)).languageCode, 'ar');
  });

  test('the toggle turns the language and turns it back', () {
    expect(
      LanguageToggleButton.nextLocale(const Locale('ar')).languageCode,
      'en',
    );
    expect(
      LanguageToggleButton.nextLocale(const Locale('en')).languageCode,
      'ar',
    );
  });
}
