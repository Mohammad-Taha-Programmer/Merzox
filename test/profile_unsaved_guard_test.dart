import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:merzox/core/auth/secure_token_store.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/profile/bloc/profile_edit_bloc.dart';
import 'package:merzox/features/profile/bloc/profile_edit_event.dart';
import 'package:merzox/features/profile/pages/profile_edit_page.dart';
import 'package:merzox/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'localization_test_harness.dart';

/// Leaving the profile form with edits on it.
///
/// The back arrow used to close the screen and drop whatever had been typed,
/// with nothing said. It asks now - but only when there is something to ask
/// about, because a question on every exit teaches people to dismiss it
/// without reading, which is worse than not asking.

class _ProfileApi extends ApiService {
  final List<Map<String, dynamic>> saved = <Map<String, dynamic>>[];

  @override
  Future<AuthApiUser> me({required String token}) async => _user();

  @override
  Future<List<SavedAddressApiModel>> myAddresses({
    required String token,
  }) async => const <SavedAddressApiModel>[];

  @override
  Future<AuthApiUser> updateProfile({
    required String token,
    String? name,
    String? gender,
    String? birthDate,
    List<ContactEmail>? emails,
    List<ContactPhone>? phones,
  }) async {
    saved.add(<String, dynamic>{'name': name, 'gender': gender});
    return _user();
  }
}

AuthApiUser _user() => AuthApiUser.fromJson(<String, dynamic>{
  'id': 'user-1',
  'name': 'ياسمين خالد',
  'userType': 'normal',
  'gender': 'female',
  'canChangeName': true,
  'canChangeGender': true,
  'emails': <Map<String, dynamic>>[
    <String, dynamic>{'value': 'yasmeen@example.test', 'label': 'personal'},
  ],
  'phones': <Map<String, dynamic>>[
    <String, dynamic>{'value': '0592029316', 'label': 'mobile'},
  ],
});

Future<_ProfileApi> _pumpForm(
  WidgetTester tester, {
  /// Tall by default so the whole form lays out at once. A test about
  /// scrolling asks for a phone, where the save button is below the fold.
  Size surface = const Size(1000, 2400),
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    AuthBloc.sessionKey: true,
    AuthBloc.userTypeKey: 'normal',
  });
  FlutterSecureStorage.setMockInitialValues(<String, String>{
    SecureTokenStore.key: 'token',
  });

  final _ProfileApi api = _ProfileApi();
  final ProfileEditBloc bloc = ProfileEditBloc(apiService: api);
  addTearDown(bloc.close);
  bloc.add(const ProfileEditStarted());

  // The form is pushed onto a screen rather than opened as the first one:
  // `context.pop()` has nothing to return to at the root of a router, so a
  // test that started there could never tell leaving from staying.
  final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('elsewhere')),
        routes: <RouteBase>[
          GoRoute(
            path: 'profile/edit',
            builder: (_, _) => BlocProvider<ProfileEditBloc>.value(
              value: bloc,
              child: ProfileEditPage(apiService: api),
            ),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  // The page leaves through `context.pop()`, which is GoRouter's, so the test
  // needs a real router above it rather than the plain MaterialApp the shared
  // harness builds.
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router,
      builder: (BuildContext context, Widget? child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
    ),
  );
  await settleFrames(tester);

  router.push('/profile/edit');
  await settleFrames(tester);

  return api;
}

/// Whether the form is still the screen in front of the reader.
bool _stillOnForm(WidgetTester tester) =>
    find.byType(ProfileEditPage).evaluate().isNotEmpty;

Future<void> _tapBack(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
  await settleFrames(tester);
}

Finder _dialog() =>
    find.byKey(const ValueKey<String>('profileEdit.unsavedDialog'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  testWidgets('leaving an untouched form asks nothing', (tester) async {
    await _pumpForm(tester);
    await _tapBack(tester);

    expect(_dialog(), findsNothing);
    expect(_stillOnForm(tester), isFalse);
  });

  testWidgets('leaving an edited one asks first', (tester) async {
    await _pumpForm(tester);

    await tester.enterText(find.byType(TextFormField).first, 'ياسمين محمد');
    await settleFrames(tester);
    await _tapBack(tester);

    expect(_dialog(), findsOneWidget);
    expect(find.text('profileEdit.saveChangesTitle'.tr()), findsOneWidget);
    // And it has not left yet: the question is asked in front of the form.
    expect(_stillOnForm(tester), isTrue);
  });

  testWidgets('no throws the edits away and goes', (tester) async {
    final _ProfileApi api = await _pumpForm(tester);

    await tester.enterText(find.byType(TextFormField).first, 'ياسمين محمد');
    await settleFrames(tester);
    await _tapBack(tester);

    await tester.tap(find.byKey(const ValueKey<String>('profileEdit.unsavedNo')));
    await settleFrames(tester);

    expect(api.saved, isEmpty);
    expect(_stillOnForm(tester), isFalse);
  });

  testWidgets('yes hands the form back, edits intact and unsaved', (
    tester,
  ) async {
    // Yes does not save on the reader's behalf. It is how they say they did
    // not mean to leave, and what they get back is the form as they left it -
    // with the save button where it always was.
    final _ProfileApi api = await _pumpForm(tester);

    await tester.enterText(find.byType(TextFormField).first, 'ياسمين محمد');
    await settleFrames(tester);
    await _tapBack(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('profileEdit.unsavedYes')),
    );
    await settleFrames(tester);

    expect(_dialog(), findsNothing);
    expect(_stillOnForm(tester), isTrue);
    expect(api.saved, isEmpty);
    expect(find.text('ياسمين محمد'), findsOneWidget);
  });

  testWidgets('yes carries the reader down to the save button', (
    tester,
  ) async {
    // Being told to press a button one cannot see is not being told anything:
    // on a phone the save button sits a screen below the name field the edit
    // was made in. The position is read rather than the button's rectangle,
    // because a `ListView` does not build what is far below the fold - which
    // is exactly how the first attempt at this silently did nothing.
    await _pumpForm(tester, surface: const Size(375, 812));

    await tester.enterText(find.byType(TextFormField).first, 'ياسمين محمد');
    await settleFrames(tester);

    final ScrollableState list = tester.state(find.byType(Scrollable).first);
    expect(list.position.pixels, 0, reason: 'starts at the top of the form');
    expect(list.position.maxScrollExtent, greaterThan(0));

    await _tapBack(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('profileEdit.unsavedYes')),
    );
    await settleFrames(tester);

    expect(list.position.pixels, list.position.maxScrollExtent);
    expect(_stillOnForm(tester), isTrue);
  });

  testWidgets('a dismissal carries them nowhere', (tester) async {
    // Neither answer was given, so the screen does not act on one.
    await _pumpForm(tester, surface: const Size(375, 812));

    await tester.enterText(find.byType(TextFormField).first, 'ياسمين محمد');
    await settleFrames(tester);
    await _tapBack(tester);

    final ScrollableState list = tester.state(find.byType(Scrollable).first);
    final double before = list.position.pixels;

    // Outside the dialog, which is how a reader dismisses one.
    await tester.tapAt(const Offset(10, 10));
    await settleFrames(tester);

    expect(_dialog(), findsNothing);
    expect(list.position.pixels, before);
  });

  testWidgets('and the page own save is what stores them', (tester) async {
    final _ProfileApi api = await _pumpForm(tester);

    await tester.enterText(find.byType(TextFormField).first, 'ياسمين محمد');
    await settleFrames(tester);
    await _tapBack(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('profileEdit.unsavedYes')),
    );
    await settleFrames(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'common.save'.tr()));
    await settleFrames(tester);

    expect(api.saved.single['name'], 'ياسمين محمد');

    // And now there is nothing outstanding: the account came back, the form
    // was re-adopted from it, and leaving asks nothing.
    await _tapBack(tester);

    expect(_dialog(), findsNothing);
    expect(_stillOnForm(tester), isFalse);
  });
}
