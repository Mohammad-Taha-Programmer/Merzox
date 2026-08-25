import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/business/enrollment/business_enrollment_bloc.dart';
import 'package:merzox/features/business/enrollment/business_enrollment_page.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/features/business/settings/store_settings_page.dart';
import 'package:merzox/features/business/shell/business_bloc.dart';

import 'localization_test_harness.dart';

const _business = OwnerBusiness(
  id: 'localization-business',
  name: 'Localization Store',
  englishName: 'Localization Store EN',
  description: 'Business description',
  category: 'Retail',
  address: 'Ramallah',
  attachmentUrl: 'https://example.com/registration.pdf',
);

void _expectDirection(
  WidgetTester tester,
  Finder finder,
  TextDirection expected,
) {
  expect(finder, findsOneWidget);
  expect(Directionality.of(tester.element(finder)), expected);
}

Future<void> _pumpEnrollment(
  WidgetTester tester, {
  required TextDirection direction,
}) async {
  // BlocProvider.value deliberately does not own/close the bloc. Closing an
  // async bloc during a widget-test fake clock can stall teardown.
  final bloc = BusinessEnrollmentBloc();

  await pumpLocalized(
    tester,
    BlocProvider<BusinessEnrollmentBloc>.value(
      value: bloc,
      child: BusinessEnrollmentPage(onCompleted: () {}),
    ),
    textDirection: direction,
  );
}

Future<void> _pumpSettings(
  WidgetTester tester, {
  required TextDirection direction,
}) async {
  // This bloc is only a provider dependency for this rendering test.
  final bloc = BusinessBloc();

  await pumpLocalized(
    tester,
    BlocProvider<BusinessBloc>.value(
      value: bloc,
      child: const StoreSettingsPage(business: _business),
    ),
    textDirection: direction,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final language in ['ar', 'en']) {
    group('GAP-015B $language localization', () {
      // File I/O must happen outside testWidgets' fake clock.
      setUpAll(() async {
        await loadAppTranslations(languageCode: language);
      });

      testWidgets('business enrollment renders both steps in app direction', (
        tester,
      ) async {
        final isArabic = language == 'ar';
        final direction = isArabic ? TextDirection.rtl : TextDirection.ltr;

        final title = isArabic
            ? 'إنشاء حساب الأعمال'
            : 'Create business account';

        final phoneLabel = isArabic ? 'رقم الجوال' : 'Mobile number';
        final next = isArabic ? 'التالي' : 'Next';

        final storeName = isArabic ? 'اسم المتجر' : 'Store name';
        final storeAddress = isArabic ? 'عنوان المتجر' : 'Store address';
        final submit = isArabic ? 'إنشاء الحساب' : 'Create account';

        await _pumpEnrollment(tester, direction: direction);

        expect(find.text(title), findsOneWidget);
        expect(find.text(phoneLabel), findsOneWidget);
        expect(find.text(next), findsOneWidget);

        _expectDirection(tester, find.text(title), direction);

        final firstStepFields = find.byType(TextFormField);
        expect(firstStepFields, findsNWidgets(3));

        await tester.enterText(firstStepFields.at(0), '+972590000000');
        await tester.enterText(firstStepFields.at(1), 'merchant@example.com');
        await tester.enterText(firstStepFields.at(2), 'secret12');

        await tester.tap(find.text(next));
        await settleFrames(tester);

        expect(find.text(storeName), findsOneWidget);
        expect(find.text(storeAddress), findsOneWidget);
        expect(find.text(submit), findsOneWidget);

        _expectDirection(tester, find.text(submit), direction);
      });

      testWidgets('Store Settings renders in app direction', (tester) async {
        final isArabic = language == 'ar';
        final direction = isArabic ? TextDirection.rtl : TextDirection.ltr;

        final title = isArabic ? 'إعدادات المتجر' : 'Store settings';
        final storeName = isArabic ? 'اسم المتجر' : 'Store name';
        final address = isArabic ? 'العنوان' : 'Address';
        final category = isArabic ? 'التصنيف' : 'Category';
        final save = isArabic ? 'حفظ' : 'Save';

        await _pumpSettings(tester, direction: direction);

        expect(find.text(title), findsOneWidget);
        expect(find.text(storeName), findsOneWidget);
        expect(find.text(address), findsOneWidget);
        expect(find.text(category), findsOneWidget);
        expect(find.text(save), findsOneWidget);

        _expectDirection(tester, find.text(title), direction);
        _expectDirection(tester, find.text(save), direction);
      });
    });
  }
}
