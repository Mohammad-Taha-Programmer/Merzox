import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/home/home_screen.dart';
import 'package:merzox/features/home/presentation/bloc/home_bloc.dart';
import 'package:merzox/features/profile/bloc/profile_edit_bloc.dart';
import 'package:merzox/features/profile/pages/profile_edit_page.dart';
import 'package:merzox/features/search/bloc/search_bloc.dart';
import 'package:merzox/features/search/pages/search_page.dart';

import 'localization_test_harness.dart';

void _expectDirection(
  WidgetTester tester,
  Finder finder,
  TextDirection expected,
) {
  expect(finder, findsOneWidget);
  expect(Directionality.of(tester.element(finder)), expected);
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required TextDirection direction,
}) async {
  // Rendering contract only. No HomeStarted event is dispatched, therefore
  // this test does not perform catalog, location, or session I/O.
  final bloc = HomeBloc();

  await pumpLocalized(
    tester,
    BlocProvider<HomeBloc>.value(
      value: bloc,
      child: const HomeScreen(isGuest: true),
    ),
    textDirection: direction,
  );
}

Future<void> _pumpProfile(
  WidgetTester tester, {
  required TextDirection direction,
}) async {
  // Initial state renders the editable shell without ProfileEditStarted, so
  // no authenticated API request is made by this localization test.
  final bloc = ProfileEditBloc();

  await pumpLocalized(
    tester,
    BlocProvider<ProfileEditBloc>.value(
      value: bloc,
      child: const ProfileEditPage(),
    ),
    textDirection: direction,
  );
}

Future<void> _pumpSearch(
  WidgetTester tester, {
  required TextDirection direction,
}) async {
  // No SearchStarted/SearchSubmitted event is dispatched. The empty initial
  // history intentionally renders the localized default-history suggestions.
  final bloc = SearchBloc();

  await pumpLocalized(
    tester,
    BlocProvider<SearchBloc>.value(value: bloc, child: const SearchPage()),
    textDirection: direction,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final language in ['ar', 'en']) {
    group('GAP-015C $language localization', () {
      // Real file I/O must happen outside testWidgets' fake clock.
      setUpAll(() async {
        await loadAppTranslations(languageCode: language);
      });

      testWidgets('Home renders localized guest shell in app direction', (
        tester,
      ) async {
        final isArabic = language == 'ar';
        final direction = isArabic ? TextDirection.rtl : TextDirection.ltr;

        final greeting = isArabic ? 'أهلاً، ضيف' : 'Hello, guest';
        final browseOnly = isArabic ? 'تصفح فقط' : 'Browse only';
        final newBusinesses = isArabic ? 'متاجر جديدة' : 'New businesses';
        final merchantTitle = isArabic
            ? 'ادخل وكن من أفضل التجار'
            : 'Join and become one of the top merchants';

        await _pumpHome(tester, direction: direction);

        expect(find.text(greeting), findsOneWidget);
        expect(find.text(browseOnly), findsOneWidget);
        expect(find.text(newBusinesses), findsOneWidget);
        expect(find.text(merchantTitle), findsOneWidget);

        _expectDirection(tester, find.text(greeting), direction);
        _expectDirection(tester, find.text(newBusinesses), direction);
      });

      testWidgets('Profile Edit renders localized form in app direction', (
        tester,
      ) async {
        final isArabic = language == 'ar';
        final direction = isArabic ? TextDirection.rtl : TextDirection.ltr;

        final title = isArabic ? 'تعديل الملف الشخصي' : 'Edit profile';
        final addEmail = isArabic ? 'إضافة بريد آخر' : 'Add another email';
        final gender = isArabic ? 'الجنس' : 'Gender';
        final save = isArabic ? 'حفظ' : 'Save';
        final other = isArabic ? 'آخر' : 'Other';

        await _pumpProfile(tester, direction: direction);

        expect(find.text(title), findsOneWidget);
        expect(find.text(addEmail), findsOneWidget);
        expect(find.text(gender), findsOneWidget);
        expect(find.text(save), findsOneWidget);

        _expectDirection(tester, find.text(title), direction);
        _expectDirection(tester, find.text(save), direction);

        // This exercises the display side of the contact-label map while the
        // stored/API identifier remains the literal internal value `other`.
        await tester.tap(find.text(addEmail));
        await settleFrames(tester);

        expect(find.text(other), findsOneWidget);
        _expectDirection(tester, find.text(other), direction);
      });

      testWidgets('Search renders localized history and directional UI', (
        tester,
      ) async {
        final isArabic = language == 'ar';
        final direction = isArabic ? TextDirection.rtl : TextDirection.ltr;

        final title = isArabic ? 'البحث' : 'Search';
        final previous = isArabic
            ? 'تم البحث عنه سابقاً'
            : 'Previously searched';
        final firstHistory = isArabic ? 'حذاء حريمي' : "Women's shoes";

        await _pumpSearch(tester, direction: direction);

        expect(find.text(title), findsOneWidget);
        expect(find.text(previous), findsOneWidget);
        expect(find.text(firstHistory), findsOneWidget);

        _expectDirection(tester, find.text(title), direction);
        _expectDirection(tester, find.text(firstHistory), direction);

        final searchField = tester.widget<TextField>(
          find.byType(TextField).first,
        );
        expect(searchField.textAlign, TextAlign.start);

        expect(
          find.byIcon(
            isArabic ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
          ),
          findsOneWidget,
        );
      });
    });
  }
}
