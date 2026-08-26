import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/localization/api_error_localizer.dart';

import 'localization_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const expectations = {
    'ar': {
      'apiErrors.contract': 'تعذر قراءة رد الخادم. حاول مرة أخرى.',
      'apiErrors.connection':
          'تعذر الاتصال بالخادم. تأكد من تشغيل Backend Merzox.',
      'apiErrors.unexpected': 'حدث خطأ غير متوقع، حاول مرة أخرى',
    },
    'en': {
      'apiErrors.contract':
          'Could not read the server response. Please try again.',
      'apiErrors.connection':
          'Could not connect to the server. '
          'Make sure the Merzox backend is running.',
      'apiErrors.unexpected': 'An unexpected error occurred. Please try again.',
    },
  };

  for (final language in expectations.keys) {
    test('API fallback keys localize in $language', () async {
      await loadAppTranslations(languageCode: language);

      final expected = expectations[language]!;

      for (final entry in expected.entries) {
        expect(
          localizeApiErrorOrRaw(entry.key),
          entry.value,
          reason: '${entry.key} / $language',
        );
      }
    });
  }

  test('raw backend messages are never interpreted as API keys', () async {
    await loadAppTranslations(languageCode: 'en');

    const raw = 'Server says no. Please retry.';

    expect(localizeApiErrorOrRaw(raw), raw);
  });
}
