import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:merzox/core/localization/api_error_localizer.dart';
import 'package:merzox/features/profile/bloc/profile_edit_bloc.dart';
import 'package:merzox/features/profile/bloc/profile_edit_event.dart';
import 'package:merzox/features/profile/bloc/profile_edit_state.dart';
import 'package:merzox/features/profile/pages/profile_edit_page.dart';
import 'package:merzox/services/api_service.dart';

import 'auth_session_fixtures.dart';
import 'localization_test_harness.dart';

/// MERZOX-UI-002.
///
/// Date of birth is a DATE-ONLY value carried end to end as canonical
/// `YYYY-MM-DD`. These tests pin the parse, the wire shape, the bloc handoff
/// and the XD Day / Month / Year controls, which are now real state rather
/// than the previous non-interactive placeholders.

const _absent = Object();

Map<String, dynamic> _userJson({Object? birthDate = _absent}) {
  return {
    'id': 'user-1',
    'name': 'ليان',
    'address': 'رام الله',
    'userType': 'normal',
    'gender': 'female',
    'canChangeName': false,
    'canChangeGender': false,
    'emails': <dynamic>[],
    'phones': <dynamic>[],
    'permissions': const {
      'aiPersonalization': false,
      'location': false,
      'contacts': false,
    },
    if (!identical(birthDate, _absent)) 'birthDate': birthDate,
  };
}

/// A Dio that answers every profile call with [user] and records the requests.
///
/// With [hangOnPatch] the profile save never completes, which is how the page
/// is held in its saving state long enough to assert the busy behaviour.
Dio _profileDio(
  List<RequestOptions> requests,
  Map<String, dynamic> user, {
  bool hangOnPatch = false,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://example.test/api/v1'));

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        requests.add(options);

        if (hangOnPatch && options.method == 'PATCH') {
          return;
        }

        handler.resolve(
          Response<Map<String, dynamic>>(
            requestOptions: options,
            statusCode: 200,
            data: {
              'success': true,
              'data': {'user': user},
            },
          ),
        );
      },
    ),
  );

  return dio;
}

Future<void> _pumpProfileEdit(WidgetTester tester, ProfileEditBloc bloc) async {
  await pumpLocalized(
    tester,
    BlocProvider<ProfileEditBloc>.value(
      value: bloc,
      child: const ProfileEditPage(),
    ),
  );
}

/// Pumps the page inside a real router, and returns it.
///
/// A successful save is a navigating action: the page's own listener calls
/// `context.go('/home')`. The plain [pumpLocalized] harness puts no router in
/// the tree, so that production navigation throws `No GoRouter found in
/// context` and takes the assertion under test down with it. The answer is to
/// give the test the navigation environment the app really has, not to remove
/// the navigation — so the destination route below is real and the test can
/// assert the page arrived there.
Future<GoRouter> _pumpRoutedProfileEdit(
  WidgetTester tester,
  ProfileEditBloc bloc, {
  TextDirection textDirection = TextDirection.rtl,
}) async {
  // Same tall surface as [pumpLocalized]: the default viewport would push the
  // save button off-screen, where a tap silently misses.
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: _profileEditRoute,
    routes: [
      GoRoute(
        path: _profileEditRoute,
        builder: (context, state) => BlocProvider<ProfileEditBloc>.value(
          value: bloc,
          child: const ProfileEditPage(),
        ),
      ),
      GoRoute(
        path: _homeRoute,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text(_homeRouteMarker))),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router,
      builder: (context, child) =>
          Directionality(textDirection: textDirection, child: child!),
    ),
  );
  await settleFrames(tester);

  return router;
}

const _profileEditRoute = '/profile/edit';
const _homeRoute = '/home';
const _homeRouteMarker = 'home-route';

DropdownButton<int> _dropdown(WidgetTester tester, Key key) {
  return tester.widget<DropdownButton<int>>(find.byKey(key));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthApiUser birth-date contract', () {
    test('a canonical backend date is preserved verbatim', () {
      expect(
        AuthApiUser.fromJson(_userJson(birthDate: '2000-02-29')).birthDate,
        '2000-02-29',
      );
      expect(
        AuthApiUser.fromJson(_userJson(birthDate: '1994-11-07')).birthDate,
        '1994-11-07',
      );
    });

    test('a legacy user with a missing or null birth date stays null', () {
      expect(AuthApiUser.fromJson(_userJson()).birthDate, isNull);
      expect(
        AuthApiUser.fromJson(_userJson(birthDate: null)).birthDate,
        isNull,
      );
    });

    test('an impossible or malformed date never becomes a value', () {
      for (final raw in [
        '2025-02-29',
        '2026-02-30',
        '2000-13-01',
        '2000-00-01',
        '01-02-2000',
        'not-a-date',
        20000101,
        true,
      ]) {
        expect(
          AuthApiUser.fromJson(_userJson(birthDate: raw)).birthDate,
          isNull,
          reason: '$raw',
        );
      }
    });

    test('a full ISO timestamp is reduced to its calendar day', () {
      // Defensive: the calendar day must survive even if a caller ever hands
      // this contract a timestamp instead of the canonical date.
      expect(
        AuthApiUser.fromJson(
          _userJson(birthDate: '1994-11-07T00:00:00.000Z'),
        ).birthDate,
        '1994-11-07',
      );
    });

    test('the constructor keeps birth date optional for existing callers', () {
      const user = AuthApiUser(
        id: 'user-1',
        name: 'ليان',
        email: null,
        emails: [],
        phone: null,
        phones: [],
        address: '',
        userType: 'normal',
        gender: 'female',
        canChangeName: true,
        canChangeGender: true,
        permissions: UserPermissions(
          aiPersonalization: false,
          location: false,
          contacts: false,
        ),
      );

      expect(user.birthDate, isNull);
    });
  });

  group('updateProfile wire shape', () {
    test('a supplied birth date is sent as canonical YYYY-MM-DD', () async {
      final requests = <RequestOptions>[];
      final api = ApiService(
        dio: _profileDio(requests, _userJson(birthDate: '2000-02-29')),
      );

      await api.updateProfile(
        token: 'token-1',
        address: 'رام الله',
        birthDate: '2000-02-29',
      );

      expect(requests, hasLength(1));
      expect(requests.single.method, 'PATCH');
      expect(requests.single.path, '/users/me');
      expect(requests.single.data, {
        'address': 'رام الله',
        'birthDate': '2000-02-29',
      });
    });

    test('an omitted birth date is absent from the patch body', () async {
      final requests = <RequestOptions>[];
      final api = ApiService(dio: _profileDio(requests, _userJson()));

      await api.updateProfile(token: 'token-1', address: 'رام الله');

      expect(requests.single.data, {'address': 'رام الله'});
      expect((requests.single.data as Map).containsKey('birthDate'), isFalse);
    });
  });

  group('ProfileEditBloc birth-date handoff', () {
    setUp(() => useAuthenticatedSession());

    test('a submitted birth date reaches the profile patch', () async {
      final requests = <RequestOptions>[];
      final bloc = ProfileEditBloc(
        apiService: ApiService(
          dio: _profileDio(requests, _userJson(birthDate: '1994-11-07')),
        ),
      );

      bloc.add(
        const ProfileEditSubmitted(
          name: null,
          gender: null,
          address: 'رام الله',
          emails: [],
          phones: [],
          birthDate: '1994-11-07',
        ),
      );

      final state = await bloc.stream.firstWhere(
        (s) =>
            s.status == ProfileEditStatus.success ||
            s.status == ProfileEditStatus.failure,
      );
      await bloc.close();

      expect(state.status, ProfileEditStatus.success);
      expect(state.user?.birthDate, '1994-11-07');
      expect((requests.single.data as Map)['birthDate'], '1994-11-07');
    });

    test('an unset birth date never appears in the patch', () async {
      final requests = <RequestOptions>[];
      final bloc = ProfileEditBloc(
        apiService: ApiService(dio: _profileDio(requests, _userJson())),
      );

      bloc.add(
        const ProfileEditSubmitted(
          name: null,
          gender: null,
          address: 'رام الله',
          emails: [],
          phones: [],
        ),
      );

      await bloc.stream.firstWhere(
        (s) =>
            s.status == ProfileEditStatus.success ||
            s.status == ProfileEditStatus.failure,
      );
      await bloc.close();

      expect((requests.single.data as Map).containsKey('birthDate'), isFalse);
    });
  });

  group('server birth-date errors are localized, not leaked', () {
    test('INVALID_BIRTH_DATE resolves to an Arabic message', () async {
      await loadAppTranslations(languageCode: 'ar');

      final message = ApiService.messageFromError(
        DioException(
          requestOptions: RequestOptions(path: '/users/me'),
          response: Response<Map<String, dynamic>>(
            requestOptions: RequestOptions(path: '/users/me'),
            statusCode: 400,
            data: const {
              'success': false,
              'error': {
                'code': 'INVALID_BIRTH_DATE',
                'message':
                    'Date of birth must be a real past date in '
                    'YYYY-MM-DD format',
              },
            },
          ),
        ),
      );

      expect(message, 'apiErrors.invalidBirthDate');
      // The raw English server prose must never be what an Arabic user reads.
      expect(
        localizeApiErrorOrRaw(message),
        'تاريخ الميلاد غير صحيح. اختر تاريخاً حقيقياً وغير مستقبلي.',
      );
    });

    test('an unmapped server message is still passed through', () {
      final message = ApiService.messageFromError(
        DioException(
          requestOptions: RequestOptions(path: '/users/me'),
          response: Response<Map<String, dynamic>>(
            requestOptions: RequestOptions(path: '/users/me'),
            statusCode: 400,
            data: const {
              'success': false,
              'error': {'code': 'NAME_CHANGE_LIMIT', 'message': 'Name limit'},
            },
          ),
        ),
      );

      expect(message, 'Name limit');
    });
  });

  test('the non-interactive birthday placeholders are gone', () async {
    final source = await File(
      'lib/features/profile/pages/profile_edit_page.dart',
    ).readAsString();

    for (final removed in ['_BirthdayPlaceholders', '_PlaceholderDropdown']) {
      expect(
        source.contains(removed),
        isFalse,
        reason: '$removed was a fake control and must not return',
      );
    }
  });

  group('XD birth-date controls', () {
    setUpAll(() => loadAppTranslations(languageCode: 'ar'));
    setUp(() => useAuthenticatedSession());

    testWidgets('an existing birth date pre-populates all three selectors', (
      tester,
    ) async {
      final bloc = ProfileEditBloc(
        apiService: ApiService(
          dio: _profileDio(
            <RequestOptions>[],
            _userJson(birthDate: '2000-02-29'),
          ),
        ),
      );
      addTearDown(bloc.close);

      bloc.add(const ProfileEditStarted());
      await _pumpProfileEdit(tester, bloc);

      expect(_dropdown(tester, birthDayFieldKey).value, 29);
      expect(_dropdown(tester, birthMonthFieldKey).value, 2);
      expect(_dropdown(tester, birthYearFieldKey).value, 2000);
    });

    testWidgets('a legacy user keeps the Day / Month / Year placeholders', (
      tester,
    ) async {
      final bloc = ProfileEditBloc(
        apiService: ApiService(
          dio: _profileDio(<RequestOptions>[], _userJson()),
        ),
      );
      addTearDown(bloc.close);

      bloc.add(const ProfileEditStarted());
      await _pumpProfileEdit(tester, bloc);

      expect(_dropdown(tester, birthDayFieldKey).value, isNull);
      expect(_dropdown(tester, birthMonthFieldKey).value, isNull);
      expect(_dropdown(tester, birthYearFieldKey).value, isNull);

      expect(find.text('اليوم'), findsOneWidget);
      expect(find.text('الشهر'), findsOneWidget);
      expect(find.text('السنة'), findsOneWidget);
    });

    testWidgets('day choices follow the selected month and year', (
      tester,
    ) async {
      final bloc = ProfileEditBloc(
        apiService: ApiService(
          dio: _profileDio(<RequestOptions>[], _userJson()),
        ),
      );
      addTearDown(bloc.close);

      bloc.add(const ProfileEditStarted());
      await _pumpProfileEdit(tester, bloc);

      Future<void> select(Key key, int value) async {
        _dropdown(tester, key).onChanged!(value);
        await settleFrames(tester);
      }

      int dayCount() => _dropdown(tester, birthDayFieldKey).items!.length;

      await select(birthYearFieldKey, 2024);
      await select(birthMonthFieldKey, 4);
      expect(dayCount(), 30, reason: 'April has 30 days');

      await select(birthMonthFieldKey, 2);
      expect(dayCount(), 29, reason: 'February 2024 is a leap February');

      await select(birthDayFieldKey, 29);
      expect(_dropdown(tester, birthDayFieldKey).value, 29);

      // A non-leap year cannot keep the 29th, and the invalid day is cleared
      // rather than silently moved to another birthday.
      await select(birthYearFieldKey, 2025);
      expect(dayCount(), 28);
      expect(_dropdown(tester, birthDayFieldKey).value, isNull);
    });

    testWidgets('no future birth date can be selected', (tester) async {
      final bloc = ProfileEditBloc(
        apiService: ApiService(
          dio: _profileDio(<RequestOptions>[], _userJson()),
        ),
      );
      addTearDown(bloc.close);

      bloc.add(const ProfileEditStarted());
      await _pumpProfileEdit(tester, bloc);

      // The page bounds "today" on the UTC calendar day because that is what
      // the backend compares against, so the expectation reads the same clock.
      final now = DateTime.now().toUtc();

      _dropdown(tester, birthYearFieldKey).onChanged!(now.year);
      await settleFrames(tester);

      final years = _dropdown(
        tester,
        birthYearFieldKey,
      ).items!.map((item) => item.value!).toList();
      expect(years.first, now.year);
      expect(years.every((year) => year <= now.year), isTrue);

      final months = _dropdown(tester, birthMonthFieldKey).items!;
      expect(months.length, now.month);

      _dropdown(tester, birthMonthFieldKey).onChanged!(now.month);
      await settleFrames(tester);

      expect(_dropdown(tester, birthDayFieldKey).items!.length, now.day);
    });

    testWidgets('the year list carries no maximum-age cut-off', (tester) async {
      final requests = <RequestOptions>[];
      final bloc = ProfileEditBloc(
        apiService: ApiService(dio: _profileDio(requests, _userJson())),
      );
      addTearDown(bloc.close);

      bloc.add(const ProfileEditStarted());
      // Saving succeeds here, and a successful save navigates, so this test
      // needs the router the app runs with.
      final router = await _pumpRoutedProfileEdit(tester, bloc);

      final years = _dropdown(
        tester,
        birthYearFieldKey,
      ).items!.map((item) => item.value!).toList();
      final thisYear = DateTime.now().toUtc().year;

      // A 120-year span — or any other invented age limit — would end the list
      // well short of these. The floor is the Gregorian calendar itself.
      expect(years, contains(1800));
      expect(years, contains(thisYear - 121));
      expect(years.last, 1);
      expect(years, hasLength(thisYear));

      Future<void> select(Key key, int value) async {
        _dropdown(tester, key).onChanged!(value);
        await settleFrames(tester);
      }

      // Selectable is not enough: the old year must survive validation and
      // reach the wire as a canonical date.
      await select(birthYearFieldKey, 1800);
      await select(birthMonthFieldKey, 5);
      await select(birthDayFieldKey, 4);

      expect(_dropdown(tester, birthYearFieldKey).value, 1800);

      await tester.tap(find.text('حفظ'));
      await settleFrames(tester);

      final patch = requests.firstWhere((request) => request.method == 'PATCH');
      expect((patch.data as Map)['birthDate'], '1800-05-04');

      // The save really did succeed, rather than the page merely surviving: the
      // production success listener ran its navigation to completion.
      expect(router.routerDelegate.currentConfiguration.uri.path, _homeRoute);
      expect(find.text(_homeRouteMarker), findsOneWidget);
    });

    testWidgets('a partial birth date is refused before any request', (
      tester,
    ) async {
      final requests = <RequestOptions>[];
      final bloc = ProfileEditBloc(
        apiService: ApiService(dio: _profileDio(requests, _userJson())),
      );
      addTearDown(bloc.close);

      bloc.add(const ProfileEditStarted());
      await _pumpProfileEdit(tester, bloc);

      expect(requests, hasLength(1), reason: 'only the initial GET so far');

      _dropdown(tester, birthYearFieldKey).onChanged!(1994);
      await settleFrames(tester);

      await tester.tap(find.text('حفظ'));
      await settleFrames(tester);

      expect(
        find.text('اختر اليوم والشهر والسنة لتاريخ الميلاد'),
        findsOneWidget,
      );
      expect(requests, hasLength(1), reason: 'no profile PATCH was issued');
    });

    testWidgets('the selectors are disabled while the profile is busy', (
      tester,
    ) async {
      final requests = <RequestOptions>[];
      final bloc = ProfileEditBloc(
        apiService: ApiService(
          dio: _profileDio(
            requests,
            _userJson(birthDate: '1994-11-07'),
            hangOnPatch: true,
          ),
        ),
      );
      // Deliberately not closed: the save handler is still in flight, and
      // closing a bloc mid-handler is not what this test is about.

      bloc.add(const ProfileEditStarted());
      await _pumpProfileEdit(tester, bloc);

      expect(_dropdown(tester, birthDayFieldKey).onChanged, isNotNull);

      // The save never resolves, so the page stays in its saving state.
      await tester.tap(find.text('حفظ'));
      await settleFrames(tester);

      expect(bloc.state.status, ProfileEditStatus.saving);
      expect(_dropdown(tester, birthDayFieldKey).onChanged, isNull);
      expect(_dropdown(tester, birthMonthFieldKey).onChanged, isNull);
      expect(_dropdown(tester, birthYearFieldKey).onChanged, isNull);
    });
  });
}
