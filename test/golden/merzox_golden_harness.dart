// MERZOX-UI-GOLDEN-I4-I1 - reusable native Flutter golden harness.
//
// This file owns GENERIC golden infrastructure only: the canonical capture
// surface, the bundled font loader, the Arabic localized pump, and the capture
// helper. Feature fixtures (fake APIs, seed models, bloc wiring) belong in the
// individual golden test files, never here.
//
// Scope note: these goldens are deterministic *Flutter* baselines. They are not
// evidence of Adobe XD parity - nothing here compares against an XD reference.

import 'dart:io' show Platform;

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/foundation.dart' show FlutterExceptionHandler;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// The one logical surface every Merzox golden is captured on.
///
/// The PNG written by `matchesGoldenFile` is exactly this many device pixels,
/// because [pumpMerzoxGoldenPage] pins the device pixel ratio to 1.
const Size merzoxGoldenSurfaceSize = Size(375, 812);

/// Identifies the `RepaintBoundary` that every golden is captured from.
///
/// Stable and shared, so a test never has to invent its own capture root and
/// accidentally screenshot a smaller subtree.
const Key merzoxGoldenRootKey = ValueKey<String>('merzox-golden-root');

/// Directory the seed PNGs live in, relative to `test/golden/`.
///
/// `matchesGoldenFile` resolves a relative path against the directory of the
/// test file that calls it, so this lands on `test/goldens/seed/`.
const String merzoxSeedGoldenDirectory = '../goldens/seed/';

/// The Merzox fonts declared in `pubspec.yaml`, by family.
///
/// Read through [rootBundle] rather than the filesystem so the harness stays
/// tied to the same asset bundle the app ships.
const Map<String, List<String>> merzoxGoldenFontAssets = <String, List<String>>{
  'MaterialIcons': <String>['fonts/MaterialIcons-Regular.otf'],
  'Tajawal': <String>['assets/fonts/Tajawal-Regular.ttf'],
  'Concept': <String>['assets/fonts/Concept Medium.ttf'],
  'Minion': <String>['assets/fonts/MINIONVARIABLECONCEPT-ROMAN.OTF'],
};

/// Exact-pixel goldens are renderer and platform dependent.
///
/// Windows is the canonical Merzox golden environment, so the seed suite is
/// skipped elsewhere with a stated reason instead of pretending the bytes are
/// portable.
bool get isMerzoxGoldenCanonicalPlatform => Platform.isWindows;

/// Skip argument for a golden `group`.
///
/// `null` on the canonical platform - the goldens must run there - and a
/// human-readable reason everywhere else.
String? get merzoxGoldenPlatformSkip => isMerzoxGoldenCanonicalPlatform
    ? null
    : 'Exact-pixel Merzox goldens are canonical on Windows only; '
          'the current platform is ${Platform.operatingSystem}. '
          'Regenerate and verify them on Windows.';

bool _fontsLoaded = false;

/// Loads every bundled Merzox font into the test text engine.
///
/// Idempotent, so `setUpAll` in each golden suite can call it without paying
/// for the asset reads more than once per test process. Must be called outside
/// `testWidgets` (or inside `runAsync`): the loads are real asset I/O, which
/// does not progress on the faked test clock.
/// The status-bar inset every Merzox artboard draws.
///
/// The corpus renders the 9:41 / signal / wifi strip at the top of each 375x812
/// artboard, and a `SafeArea`-wrapped screen sits below it on a real device. A
/// seed that omits this is 44px out of register with its reference.
const double merzoxGoldenStatusBarHeight = 44;

/// Wraps [page] in the device surface an artboard assumes.
///
/// Use for any screen that wraps itself in `SafeArea`. Screens that paint
/// full-bleed (the splash) do not, and must not, be wrapped.
Widget withMerzoxGoldenDeviceInsets(Widget page) {
  return MediaQuery(
    data: const MediaQueryData(
      size: merzoxGoldenSurfaceSize,
      devicePixelRatio: 1,
      padding: EdgeInsets.only(top: merzoxGoldenStatusBarHeight),
      viewPadding: EdgeInsets.only(top: merzoxGoldenStatusBarHeight),
    ),
    child: page,
  );
}

/// Loads intl's date symbols, exactly as `bootstrap()` does.
///
/// A golden captured without these would show English weekday names for an
/// Arabic screen and would therefore be a baseline of a bug rather than of the
/// shipped screen.
Future<void> loadMerzoxGoldenDateSymbols() async {
  await initializeDateFormatting();
}

Future<void> loadMerzoxGoldenFonts() async {
  if (_fontsLoaded) {
    return;
  }

  for (final MapEntry<String, List<String>> family
      in merzoxGoldenFontAssets.entries) {
    final FontLoader loader = FontLoader(family.key);
    for (final String asset in family.value) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }

  _fontsLoaded = true;
}

/// The ambient theme the seed pages are captured under.
///
/// The production theme in `lib/app/app.dart` is built inline inside
/// `MerzoxApp.build`, so there is no public object to reuse. This is the
/// minimal equivalent: the same seed colour, the same default font family and
/// the same Material version, and nothing of the router or startup wiring.
ThemeData merzoxGoldenTheme() {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3D5A80)),
    fontFamily: 'Tajawal',
    useMaterial3: true,
    brightness: Brightness.light,
  );
}

/// The full capture tree: a fixed 375x812 `RepaintBoundary` holding an Arabic
/// localized [MaterialApp] whose `home` is [page].
///
/// The `SizedBox` above the boundary is what makes the golden size a property
/// of the harness rather than of the test view: even if a caller forgets to
/// resize the surface, the captured region stays 375x812.
Widget merzoxGoldenSurface({required Widget page}) {
  return Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: merzoxGoldenSurfaceSize.width,
      height: merzoxGoldenSurfaceSize.height,
      child: RepaintBoundary(
        key: merzoxGoldenRootKey,
        child: EasyLocalization(
          supportedLocales: const <Locale>[Locale('ar'), Locale('en')],
          path: 'assets/translations',
          fallbackLocale: const Locale('ar'),
          startLocale: const Locale('ar'),
          saveLocale: false,
          child: Builder(
            builder: (BuildContext context) {
              return MaterialApp(
                debugShowCheckedModeBanner: false,
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                theme: merzoxGoldenTheme(),
                // Applied inside the app so it wins over the `MediaQuery`
                // `WidgetsApp` derives from the test view.
                builder: (BuildContext context, Widget? child) {
                  return MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.noScaling,
                      platformBrightness: Brightness.light,
                      boldText: false,
                      highContrast: false,
                      invertColors: false,
                      disableAnimations: false,
                      accessibleNavigation: false,
                    ),
                    child: child ?? const SizedBox.shrink(),
                  );
                },
                home: page,
              );
            },
          ),
        ),
      ),
    ),
  );
}

/// Renders [page] on the canonical Arabic golden surface.
///
/// Everything that needs real asset I/O - the `easy_localization` catalogue and
/// every `Image` in the tree - is resolved inside `runAsync`, because that I/O
/// never completes on the faked clock. Nothing here waits on wall-clock time:
/// images are awaited through `precacheImage`, not slept on.
Future<void> pumpMerzoxGoldenPage(WidgetTester tester, Widget page) async {
  // A golden environment has no network, on purpose: the capture must be the
  // same bytes on any machine. An `Image.network` therefore always fails here,
  // and the widget's own `errorBuilder` draws the placeholder the capture is
  // meant to show - so the failure is expected, and the only thing left to do
  // with it is not fail the test over it. Nothing else is swallowed.
  final FlutterExceptionHandler? previousOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exception is NetworkImageLoadException) return;
    previousOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = previousOnError);

  tester.view.physicalSize = merzoxGoldenSurfaceSize;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = 1.0;
  tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;

  addTearDown(() {
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
    tester.view.reset();
  });

  await tester.runAsync(() async {
    await tester.pumpWidget(merzoxGoldenSurface(page: page));

    // `EasyLocalization` resolves its catalogue asynchronously, so translated
    // widgets need one more rendered frame before they exist.
    await tester.idle();
    await tester.pump();
    await tester.idle();
    await tester.pump();

    await precacheMerzoxGoldenImages(tester);
    await tester.pump();
  });

  await settleMerzoxGoldenFrames(tester);
}

/// Awaits every `Image` currently in the tree so the capture is not racing an
/// undecoded asset.
///
/// Deterministic by construction: it waits on the image futures themselves
/// rather than on a duration. Must be called inside `runAsync`.
Future<void> precacheMerzoxGoldenImages(WidgetTester tester) async {
  await Future.wait(<Future<void>>[
    for (final Element element in find.byType(Image).evaluate())
      _precacheOne(element),
  ]);
}

/// How long one image gets before the capture stops waiting for it.
///
/// The wait exists so a capture is not racing a decode. A fetch that never
/// returns is not a race: a map's tile layer asks for images the golden
/// environment has no network to answer, and waiting on those hangs the seed
/// rather than making it deterministic. Bounding it is what keeps "wait for
/// every image" a promise that can be kept.
const Duration merzoxGoldenImageWait = Duration(seconds: 1);

Future<void> _precacheOne(Element element) async {
  final Image image = element.widget as Image;

  // An image that cannot load is not a race either: the widget's own
  // `errorBuilder` draws the placeholder, and that placeholder is what the
  // capture is meant to show.
  try {
    await precacheImage(
      image.image,
      element,
    ).timeout(merzoxGoldenImageWait, onTimeout: () {});
  } catch (_) {
    // Deliberately swallowed; see above.
  }
}

/// A bounded settle.
///
/// `pumpAndSettle` waits for the scheduler to go idle, which a screen with a
/// progress indicator never does. A fixed frame count is used instead, which is
/// also why it can never mask an endless animation: it always stops.
Future<void> settleMerzoxGoldenFrames(
  WidgetTester tester, {
  int frames = 12,
  Duration step = const Duration(milliseconds: 100),
}) async {
  for (int frame = 0; frame < frames; frame++) {
    await tester.pump(step);
  }
}

/// Captures the fixed 375x812 surface and compares it with [fileName] under
/// `test/goldens/seed/`.
Future<void> expectMerzoxSeedGolden(String fileName) {
  return expectLater(
    find.byKey(merzoxGoldenRootKey),
    matchesGoldenFile('$merzoxSeedGoldenDirectory$fileName'),
  );
}
