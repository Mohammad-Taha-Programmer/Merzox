import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/authentication/pages/login_page.dart';
import 'package:merzox/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'localization_test_harness.dart';

/// What the sign-in screen actually hands the server, from what a reader types.
///
/// [signInIdentifier] is checked on its own elsewhere; this reads the address
/// that leaves the page, so the rule being right is not confused with the page
/// using it.
class _RecordingLoginApi extends ApiService {
  String? identifier;

  @override
  Future<AuthApiResponse> login({
    required String identifier,
    required String password,
  }) async {
    this.identifier = identifier;

    // Recorded, then refused. Signing in for real would put the test through
    // session storage and the realtime handshake, none of which this is about.
    throw StateError('no server in this test');
  }
}

Future<String?> _identifierSentBy(
  WidgetTester tester, {
  required String typed,
  bool businessMode = false,
  String? pickCountry,
}) async {
  final api = _RecordingLoginApi();
  final bloc = AuthBloc(apiService: api);
  addTearDown(bloc.close);

  await pumpLocalized(
    tester,
    BlocProvider<AuthBloc>.value(value: bloc, child: _page(businessMode)),
  );

  if (pickCountry != null) {
    await tester.tap(find.byKey(const Key('login.countryCode')));
    await settleFrames(tester);
    await tester.tap(find.text(pickCountry).last);
    await settleFrames(tester);
  }

  await tester.enterText(_field('login.identifier'), typed);
  await tester.enterText(_field('login.password'), 'secret-123');
  await tester.tap(find.byKey(const Key('login.submit')));
  await settleFrames(tester);

  return api.identifier;
}

Finder _field(String key) => find.descendant(
  of: find.byKey(Key(key)),
  matching: find.byType(TextFormField),
);

Widget _page(bool businessMode) => LoginPage(
  businessMode: businessMode,
  onAuthenticated: () {},
  onBrowseAsGuest: () {},
  onSignupRequested: () {},
  onForgotPasswordRequested: () {},
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadAppTranslations();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  // The list opens on Palestine, so a reader who types their number without
  // touching the flag is taken at that word. The default is pinned here by what
  // it does rather than by what it paints: a default nobody checks is a default
  // that drifts.
  testWidgets('a local number leaves with the flag the list opens on', (
    tester,
  ) async {
    expect(
      await _identifierSentBy(tester, typed: '0592029316'),
      '+970592029316',
    );
  });

  testWidgets('two leading zeros leave as the plus the server stores', (
    tester,
  ) async {
    expect(
      await _identifierSentBy(tester, typed: '00972592029316'),
      '+972592029316',
    );
  });

  testWidgets('a number written with a plus leaves exactly as it came', (
    tester,
  ) async {
    expect(
      await _identifierSentBy(tester, typed: '+972592029316'),
      '+972592029316',
    );
  });

  testWidgets('the flag that is picked is the country that is used', (
    tester,
  ) async {
    expect(
      await _identifierSentBy(tester, typed: '0592029316', pickCountry: '+972'),
      '+972592029316',
    );
  });

  testWidgets('the merchant screen sends the same number as the customer', (
    tester,
  ) async {
    expect(
      await _identifierSentBy(
        tester,
        typed: '00972592029316',
        businessMode: true,
      ),
      '+972592029316',
    );
  });

  testWidgets('an email is not given a country code', (tester) async {
    expect(
      await _identifierSentBy(tester, typed: 'user@example.com'),
      'user@example.com',
    );
  });
}
