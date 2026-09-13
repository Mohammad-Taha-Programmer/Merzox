import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:merzox/core/widgets/merzox_icons.dart';
import 'package:merzox/features/home/home_screen.dart';
import 'package:merzox/features/home/presentation/bloc/home_bloc.dart';

import 'localization_test_harness.dart';

/// The account figure in the guest's top bar is the way in.
///
/// A guest has no account, and this is the only mark on the screen that stands
/// for one. It used to be a label: the one thing shaped like a button that did
/// nothing when it was pressed.
///
/// The real screen is mounted rather than a copy of the bar, because the claim
/// being tested is about where a tap goes, and where a tap goes is decided at
/// the screen and not in the widget that was pressed.
const ValueKey<String> _signIn = ValueKey<String>('merzox.home.guestSignIn');

/// No `HomeStarted` is dispatched, so the shell renders without catalog,
/// location or session work.
GoRouter _router({required bool isGuest}) => GoRouter(
  initialLocation: '/home',
  routes: <RouteBase>[
    GoRoute(
      path: '/home',
      builder: (_, _) => BlocProvider<HomeBloc>(
        create: (_) => HomeBloc(),
        child: HomeScreen(isGuest: isGuest),
      ),
    ),
    GoRoute(
      path: '/login',
      builder: (_, _) => const Scaffold(body: Text('the sign-in screen')),
    ),
  ],
);

Future<GoRouter> _pump(WidgetTester tester, {required bool isGuest}) async {
  final GoRouter router = _router(isGuest: isGuest);
  addTearDown(router.dispose);

  tester.view.physicalSize = const Size(1000, 2400);
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

  return router;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadAppTranslations();
  });

  testWidgets('a guest pressing the figure arrives at the sign-in screen', (
    tester,
  ) async {
    final GoRouter router = await _pump(tester, isGuest: true);

    expect(router.state.uri.toString(), '/home');

    await tester.tap(find.byKey(_signIn));
    await settleFrames(tester);

    expect(router.state.uri.toString(), '/login');
    expect(find.text('the sign-in screen'), findsOneWidget);
  });

  // Straight there, rather than through the dialog the guest's bell opens. The
  // figure has already said what it is for, so being asked again would be a
  // question with one answer.
  testWidgets('it does not stop to ask first', (tester) async {
    await _pump(tester, isGuest: true);

    await tester.tap(find.byKey(_signIn));
    await tester.pump();

    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a signed-in reader is not offered it', (tester) async {
    await _pump(tester, isGuest: false);

    expect(find.byKey(_signIn), findsNothing);
  });

  // The figure survives either way: it was moved into a widget of its own to
  // make it pressable, and a refactor that dropped it for one of the two states
  // would leave a bar with a greeting and nothing in front of it.
  testWidgets('the figure is drawn in both states', (tester) async {
    for (final bool isGuest in <bool>[true, false]) {
      await _pump(tester, isGuest: isGuest);

      expect(
        find.byIcon(MerzoxIcons.homeScreenProfile),
        findsOneWidget,
        reason: 'the account mark is missing for isGuest: $isGuest',
      );
    }
  });
}
