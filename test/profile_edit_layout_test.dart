import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/notifications/widgets/global_notification_bell.dart';
import 'package:merzox/features/profile/bloc/profile_edit_bloc.dart';
import 'package:merzox/features/profile/bloc/profile_edit_event.dart';
import 'package:merzox/features/profile/pages/profile_edit_page.dart';
import 'package:merzox/services/api_service.dart';

import 'auth_session_fixtures.dart';
import 'golden/merzox_golden_harness.dart';
import 'localization_test_harness.dart';

/// Three things this screen places against something outside itself, and was
/// getting wrong: the reading direction, the bell that floats above every
/// screen, and the label a control answers to.

const double _surface = 375;

Dio _profileDio() {
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://example.test/api/v1'));

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        handler.resolve(
          Response<Map<String, dynamic>>(
            requestOptions: options,
            statusCode: 200,
            data: const <String, dynamic>{
              'success': true,
              'data': <String, dynamic>{
                'user': <String, dynamic>{
                  'id': 'user-1',
                  'name': 'ليان',
                  'address': 'رام الله',
                  'userType': 'normal',
                  'gender': 'female',
                  'canChangeName': true,
                  'canChangeGender': true,
                  'emails': <dynamic>[],
                  'phones': <dynamic>[],
                  'permissions': <String, dynamic>{
                    'aiPersonalization': false,
                    'location': false,
                    'contacts': false,
                  },
                },
              },
            },
          ),
        );
      },
    ),
  );

  return dio;
}

Future<void> _pumpHeader(
  WidgetTester tester, {
  double scale = 1.0,
  TextDirection direction = TextDirection.rtl,
}) async {
  await pumpMerzoxGoldenPage(
    tester,
    withMerzoxGoldenDeviceInsets(
      Directionality(
        textDirection: direction,
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            backgroundColor: Colors.white,
            body: ProfileEditHeader(onBack: () {}),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
    await loadMerzoxGoldenFonts();
  });

  group('the way back', () {
    testWidgets('is the back icon, and Material turns it round itself', (
      WidgetTester tester,
    ) async {
      await _pumpHeader(tester);

      // The bar used to choose the forward arrow when the reading was
      // right-to-left. This icon carries `matchTextDirection`, so that turned
      // it a second time and Arabic ended up with the English arrow. Naming
      // the back arrow and letting Material turn it is the whole fix, and
      // these two facts are what keep it fixed.
      expect(find.byIcon(Icons.arrow_forward_ios_rounded), findsNothing);

      final Icon icon = tester.widget<Icon>(
        find.byIcon(Icons.arrow_back_ios_new_rounded),
      );

      expect(icon.icon!.matchTextDirection, isTrue);
    });

    testWidgets('sits at the reading edge in both directions', (
      WidgetTester tester,
    ) async {
      await _pumpHeader(tester);

      expect(
        tester.getRect(find.byIcon(Icons.arrow_back_ios_new_rounded)).center.dx,
        greaterThan(_surface / 2),
      );

      await _pumpHeader(tester, direction: TextDirection.ltr);

      expect(
        tester.getRect(find.byIcon(Icons.arrow_back_ios_new_rounded)).center.dx,
        lessThan(_surface / 2),
      );
    });
  });

  group('the language toggle and the bell', () {
    // The bell hangs at `end: kGlobalBellInset` and is
    // `kGlobalBellReservedWidth` across, so it owns the trailing corner out to
    // here. The globe stood under it and was half covered.
    const double bellReaches = kGlobalBellInset + kGlobalBellReservedWidth;

    testWidgets('the globe stands clear of the corner the bell floats in', (
      WidgetTester tester,
    ) async {
      await _pumpHeader(tester);

      expect(
        tester.getRect(find.byIcon(Icons.language_rounded)).left,
        greaterThanOrEqualTo(bellReaches),
      );
    });

    testWidgets('and stands midway between the bell and the title', (
      WidgetTester tester,
    ) async {
      await _pumpHeader(tester);

      final Rect globe = tester.getRect(find.byIcon(Icons.language_rounded));
      final Rect title = tester.getRect(find.text('تعديل الملف الشخصي'));

      // What the eye has to go on is the bell's glyph, not its disc: the disc
      // is white on a white bar. The glyph ends here - the bell's inset, its
      // own padding, its icon - and the globe should sit as far from it as it
      // does from the first letter of the title.
      const double bellGlyphEnds = kGlobalBellInset + 8 + 24;

      final double toTheBell = globe.left - bellGlyphEnds;
      final double toTheTitle = title.left - globe.right;

      expect(toTheBell, greaterThan(0));
      expect(toTheTitle, closeTo(toTheBell, 2));
    });

    testWidgets('and keeps the same clearance the other way round', (
      WidgetTester tester,
    ) async {
      await _pumpHeader(tester, direction: TextDirection.ltr);

      expect(
        tester.getRect(find.byIcon(Icons.language_rounded)).right,
        lessThanOrEqualTo(_surface - bellReaches),
      );
    });
  });

  group('the title keeps out of both', () {
    // The reader's own phone is set to 1.3. Unbounded, the title is 243 wide
    // there and runs straight through the globe it now shares the bar with.
    for (final double scale in <double>[1.0, 1.3, 2.0]) {
      testWidgets('at a font scale of $scale', (WidgetTester tester) async {
        await _pumpHeader(tester, scale: scale);

        final Rect title = tester.getRect(find.text('تعديل الملف الشخصي'));
        final Rect globe = tester.getRect(find.byIcon(Icons.language_rounded));
        final Rect back = tester.getRect(
          find.byIcon(Icons.arrow_back_ios_new_rounded),
        );

        expect(title.left, greaterThan(globe.right));
        expect(title.right, lessThan(back.left));
      });
    }

    testWidgets('and is not made smaller at the ordinary scale', (
      WidgetTester tester,
    ) async {
      await _pumpHeader(tester);

      final Rect title = tester.getRect(find.text('تعديل الملف الشخصي'));

      // The bound is room to grow into, not a smaller title: at 1.0 the words
      // are drawn at the size the board sets, centred on the screen.
      expect(title.width, closeTo(186.8, 1));
      expect(title.center.dx, closeTo(_surface / 2, 1));
    });
  });

  group('the Save button', () {
    testWidgets('follows the last field rather than being stranded', (
      WidgetTester tester,
    ) async {
      useAuthenticatedSession();

      final ProfileEditBloc bloc = ProfileEditBloc(
        apiService: ApiService(dio: _profileDio()),
      );
      addTearDown(bloc.close);

      bloc.add(const ProfileEditStarted());

      await pumpLocalized(
        tester,
        BlocProvider<ProfileEditBloc>.value(
          value: bloc,
          child: const ProfileEditPage(),
        ),
      );

      // The bordered box, not the dropdown inside it: the box is what the
      // reader sees the white start below.
      final Rect birthDate = tester.getRect(
        find.ancestor(
          of: find.byKey(birthYearFieldKey),
          matching: find.byType(InputDecorator),
        ),
      );
      final Rect save = tester.getRect(
        find.widgetWithText(FilledButton, 'حفظ'),
      );

      // The gap was 124 and the button read as belonging to nothing. It is
      // measured from the bottom of the last control, so it holds whatever
      // the birth-date row grows to.
      expect(save.top - birthDate.bottom, closeTo(kProfileSaveGap, 1));
    });
  });

  group('the gender choices', () {
    testWidgets('stand under the word they answer', (
      WidgetTester tester,
    ) async {
      useAuthenticatedSession();

      final ProfileEditBloc bloc = ProfileEditBloc(
        apiService: ApiService(dio: _profileDio()),
      );
      addTearDown(bloc.close);

      // The load is driven by the pump, not awaited before it: the bloc reads
      // the stored session, and that only progresses while frames are running.
      bloc.add(const ProfileEditStarted());

      await pumpLocalized(
        tester,
        BlocProvider<ProfileEditBloc>.value(
          value: bloc,
          child: const ProfileEditPage(),
        ),
      );

      final Rect label = tester.getRect(find.text('الجنس'));
      final Rect female = tester.getRect(find.text('أنثى'));
      final Rect male = tester.getRect(find.text('ذكر'));

      // They used to sit at the far end of the line, across the screen from
      // the word they answer. Reading right to left, they now begin where it
      // begins.
      expect(female.right, closeTo(label.right, 2));
      expect(male.right, lessThan(female.right));
    });
  });
}
