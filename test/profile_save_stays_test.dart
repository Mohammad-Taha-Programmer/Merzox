import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:merzox/features/profile/bloc/profile_edit_bloc.dart';
import 'package:merzox/features/profile/bloc/profile_edit_event.dart';
import 'package:merzox/features/profile/pages/profile_edit_page.dart';
import 'package:merzox/services/api_service.dart';

import 'auth_session_fixtures.dart';
import 'localization_test_harness.dart';

/// Saving is not leaving.
///
/// The page used to call `context.go('/home')` the moment a save succeeded.
/// For a shopkeeper who had opened their personal details from the merchant
/// side, that landed them on the customer home - the app appeared to change
/// sides under them because they had added an email address.

const String _profileEditRoute = '/profile/edit';
const String _homeRoute = '/home';
const String _homeMarker = 'home-route';

Map<String, dynamic> _user({
  List<Map<String, dynamic>> emails = const <Map<String, dynamic>>[],
  bool canChangeName = true,
}) {
  return <String, dynamic>{
    'id': 'user-1',
    'name': 'ليان',
    'address': 'رام الله',
    'userType': 'business',
    'gender': 'female',
    'canChangeName': canChangeName,
    'canChangeGender': true,
    'emails': emails,
    'phones': const <dynamic>[],
    'permissions': const <String, dynamic>{
      'aiPersonalization': false,
      'location': false,
      'contacts': false,
    },
  };
}

/// Answers the initial GET with [loaded] and the save with [saved].
Dio _dio(
  List<RequestOptions> requests, {
  required Map<String, dynamic> loaded,
  required Map<String, dynamic> saved,
}) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://example.test/api/v1'));

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        requests.add(options);

        handler.resolve(
          Response<Map<String, dynamic>>(
            requestOptions: options,
            statusCode: 200,
            data: <String, dynamic>{
              'success': true,
              'data': <String, dynamic>{
                'user': options.method == 'PATCH' ? saved : loaded,
              },
            },
          ),
        );
      },
    ),
  );

  return dio;
}

Future<GoRouter> _pumpRouted(
  WidgetTester tester,
  ProfileEditBloc bloc,
) async {
  // Tall enough that the Save button is on screen; a tap that lands off it
  // would silently do nothing and the assertion would pass for the wrong
  // reason.
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final GoRouter router = GoRouter(
    initialLocation: _profileEditRoute,
    routes: <RouteBase>[
      GoRoute(
        path: _profileEditRoute,
        builder: (BuildContext context, GoRouterState state) =>
            BlocProvider<ProfileEditBloc>.value(
              value: bloc,
              child: const ProfileEditPage(),
            ),
      ),
      GoRoute(
        path: _homeRoute,
        builder: (BuildContext context, GoRouterState state) =>
            const Scaffold(body: Center(child: Text(_homeMarker))),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router,
      builder: (BuildContext context, Widget? child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
    ),
  );
  await settleFrames(tester);

  return router;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  setUp(() => useAuthenticatedSession(business: true));

  testWidgets('adding an email and saving leaves the reader where they were', (
    WidgetTester tester,
  ) async {
    final List<RequestOptions> requests = <RequestOptions>[];
    final ProfileEditBloc bloc = ProfileEditBloc(
      apiService: ApiService(
        dio: _dio(
          requests,
          loaded: _user(),
          saved: _user(
            emails: <Map<String, dynamic>>[
              <String, dynamic>{
                'value': 'layan@merzox.test',
                'label': 'personal',
                'isPrimary': true,
              },
            ],
          ),
        ),
      ),
    );
    addTearDown(bloc.close);

    bloc.add(const ProfileEditStarted());
    final GoRouter router = await _pumpRouted(tester, bloc);

    await tester.enterText(
      find.byType(TextFormField).at(1),
      'layan@merzox.test',
    );
    await settleFrames(tester);

    await tester.tap(find.text('حفظ'));
    await settleFrames(tester);

    // The save happened, and carried the address.
    final RequestOptions patch = requests.firstWhere(
      (RequestOptions request) => request.method == 'PATCH',
    );
    expect(
      ((patch.data as Map<String, dynamic>)['emails'] as List<dynamic>).first,
      containsPair('value', 'layan@merzox.test'),
    );

    // It said so, and it stayed.
    expect(find.text('تم حفظ التعديلات'), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      _profileEditRoute,
    );
    expect(find.text(_homeMarker), findsNothing);

    // Still the same account on the same side of the app: nothing about the
    // session was touched by saving a form.
    expect(bloc.state.user?.userType, 'business');
  });

  testWidgets('a spent one-time change shows on the screen that stayed', (
    WidgetTester tester,
  ) async {
    // Now that the reader stays, the screen has to tell the truth after the
    // save as well as before it: the name may be changed once, and the server
    // says so in the response to the very save that used it up.
    final ProfileEditBloc bloc = ProfileEditBloc(
      apiService: ApiService(
        dio: _dio(
          <RequestOptions>[],
          loaded: _user(),
          saved: _user(canChangeName: false),
        ),
      ),
    );
    addTearDown(bloc.close);

    bloc.add(const ProfileEditStarted());
    await _pumpRouted(tester, bloc);

    expect(find.text('تم استخدام فرصة تعديل الاسم'), findsNothing);

    await tester.enterText(find.byType(TextFormField).first, 'ليان خالد');
    await settleFrames(tester);

    await tester.tap(find.text('حفظ'));
    await settleFrames(tester);

    expect(find.text('تم استخدام فرصة تعديل الاسم'), findsOneWidget);
  });
}
