import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/widgets/merzox_icons.dart';
import 'package:merzox/core/widgets/merzox_notched_nav_bar.dart';
import 'package:merzox/core/widgets/merzox_notched_shape.dart';

import 'golden/merzox_golden_harness.dart';
import 'localization_test_harness.dart';

/// The five places each bar draws, in the order the bar draws them.
///
/// Written out rather than read off the two bar widgets: those need a
/// `BuildContext` and translations to build, and what is being asked here is
/// about the icons themselves.
const List<IconData> _customerNavIcons = <IconData>[
  MerzoxIcons.customerNavHome,
  MerzoxIcons.customerNavCart,
  MerzoxIcons.customerNavStores,
  MerzoxIcons.customerNavMessages,
  MerzoxIcons.customerNavProfile,
];

const List<IconData> _merchantNavIcons = <IconData>[
  MerzoxIcons.merchantNavHome,
  MerzoxIcons.merchantNavOrders,
  MerzoxIcons.merchantNavAddProduct,
  MerzoxIcons.merchantNavProducts,
  MerzoxIcons.merchantNavProfile,
];

/// The bar with a bite in its top edge, and the button floating in the bite.
///
/// The old bars faked both: a white circle laid over a white bar, and a white
/// ring drawn round the button. That works only where everything behind is
/// also white, and it draws a hard circle rather than the artboard's shape.
/// So what these tests are about is the hole being a hole - geometry, not
/// appearance, since a picture of it is what the goldens already hold.

const double _width = 375;
const double _centre = _width / 2;

Rect get _host =>
    const Rect.fromLTWH(0, kMerzoxNavOverhang, _width, kMerzoxNavBarHeight);

Rect get _notch => Rect.fromCircle(
  center: const Offset(
    _centre,
    kMerzoxNavOverhang - kMerzoxNavButtonLift,
  ),
  radius: kMerzoxNavNotchRadius,
);

Offset get _buttonCentre => _notch.center;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  group('the bite in the bar', () {
    test('the bar is solid everywhere the bite is not', () {
      final Path bar = const MerzoxNotchedShape().getOuterPath(_host, _notch);

      for (final Offset point in <Offset>[
        const Offset(20, kMerzoxNavOverhang + 30),
        const Offset(_width - 20, kMerzoxNavOverhang + 30),
        const Offset(_centre, kMerzoxNavOverhang + kMerzoxNavBarHeight - 4),
      ]) {
        expect(bar.contains(point), isTrue, reason: '$point should be bar');
      }
    });

    test('the button is nowhere near it', () {
      // Every point on the button's own edge, all the way round. This is the
      // whole claim: the button floats in the bite rather than being pressed
      // into it, and a bite cut to the button's exact size would fail here.
      final Path bar = const MerzoxNotchedShape().getOuterPath(_host, _notch);

      for (int degrees = 0; degrees < 360; degrees += 5) {
        final double radians = degrees * math.pi / 180;
        final Offset edge =
            _buttonCentre +
            Offset(math.cos(radians), math.sin(radians)) *
                (kMerzoxNavButtonDiameter / 2);

        expect(
          bar.contains(edge),
          isFalse,
          reason: 'the bar reaches the button at $degrees degrees',
        );
      }
    });

    test('and the gap around it is empty the whole way out', () {
      final Path bar = const MerzoxNotchedShape().getOuterPath(_host, _notch);

      // From the button's edge to the edge of the bite. Anything solid in
      // here would be the bar touching the button.
      for (
        double out = kMerzoxNavButtonDiameter / 2;
        out < kMerzoxNavNotchRadius;
        out += 1
      ) {
        expect(
          bar.contains(_buttonCentre + Offset(0, out)),
          isFalse,
          reason: '$out below the button centre should be gap',
        );
      }

      // And immediately past it, the bar again - so the bite is a bite and
      // not simply a missing bar.
      expect(
        bar.contains(
          _buttonCentre + const Offset(0, kMerzoxNavNotchRadius + 2),
        ),
        isTrue,
      );
    });

    test('the corners where the bite meets the edge are turned, not cut', () {
      // This is the thing Flutter's own CircularNotchedRectangle does not let
      // anybody set, and the reason this shape exists. Measured rather than
      // looked at: a point just under the flat edge, out past where a sharp
      // corner would have been, is bar when the corner is sharp and gap when
      // it is turned - because turning it pulls the edge away earlier.
      //
      // The probe is placed off the bite's own edge rather than at a number:
      // it was written as a literal 36, which sat just outside a bite of 34,
      // and stopped meaning anything the day the bite grew past it - it was
      // then inside the bite, where there is no bar to find whatever the
      // corner does.
      const Offset probe = Offset(
        _centre - kMerzoxNavNotchRadius - 2,
        kMerzoxNavOverhang + 1,
      );

      final Path sharp = const MerzoxNotchedShape(
        shoulderRadius: 0,
      ).getOuterPath(_host, _notch);
      final Path turned = const MerzoxNotchedShape(
        shoulderRadius: 14,
      ).getOuterPath(_host, _notch);

      expect(sharp.contains(probe), isTrue);
      expect(turned.contains(probe), isFalse);
    });

    test('a bite too big to cut leaves the bar whole', () {
      // Refusing to draw is the point: a shape that quietly half-cut itself
      // would be a bar with a nick in it that nobody could explain.
      final Path bar = const MerzoxNotchedShape().getOuterPath(
        _host,
        Rect.fromCircle(center: const Offset(_centre, 0), radius: _width),
      );

      expect(bar.contains(const Offset(_centre, kMerzoxNavOverhang + 4)), isTrue);
    });

    test('no bite at all is just the bar', () {
      final Path bar = const MerzoxNotchedShape().getOuterPath(_host, null);

      expect(bar.contains(const Offset(_centre, kMerzoxNavOverhang + 4)), isTrue);
    });
  });

  group('the glyphs', () {
    // The bar used to draw hand-written paths, and what was held here was
    // their geometry. They come from the designer's own fonts now, so the
    // questions change: not "is this path on its grid" but "does this icon
    // reach a font at all, and is it the same picture as its neighbour".

    test('no two places in a bar wear the same picture', () {
      for (final MapEntry<String, List<IconData>> bar
          in <String, List<IconData>>{
            'customer': _customerNavIcons,
            'merchant': _merchantNavIcons,
          }.entries) {
        final Set<String> seen = <String>{};

        for (final IconData icon in bar.value) {
          expect(
            seen.add('${icon.fontFamily}:${icon.codePoint}'),
            isTrue,
            reason:
                '${bar.key}: two places draw '
                '${icon.fontFamily} U+${icon.codePoint.toRadixString(16)}',
          );
        }
      }
    });

    test('every family is declared where both readers look for it', () {
      // A family can be forgotten in two places, and the two fail differently:
      // missing from `pubspec.yaml` and the running app draws an empty box;
      // missing from the golden harness and only the captures do, which reads
      // as an icon that was never drawn rather than a font never loaded.
      // Line endings normalised first: the file is CRLF on this machine, and
      // matching a family name up to a bare newline finds nothing there while
      // reading as though the family were missing.
      final String pubspec = File(
        'pubspec.yaml',
      ).readAsStringSync().replaceAll('\r\n', '\n');

      for (final IconData icon in <IconData>[
        ..._customerNavIcons,
        ..._merchantNavIcons,
      ]) {
        final String family = icon.fontFamily!;

        expect(
          pubspec.contains('- family: $family\n'),
          isTrue,
          reason: '$family is not declared in pubspec.yaml',
        );
        expect(
          merzoxGoldenFontAssets.containsKey(family),
          isTrue,
          reason: '$family is not loaded by the golden harness',
        );
      }
    });

    test('every font the bars name is a file that exists', () {
      // Whether the code point inside each one is right is not asked here: a
      // wrong one draws the engine's empty box, which moves pixels, and both
      // bars are in the seed goldens - so that failure is already caught by a
      // picture. Reading a `cmap` in Dart to catch it twice would be a font
      // parser living in a test.
      for (final IconData icon in <IconData>[
        ..._customerNavIcons,
        ..._merchantNavIcons,
      ]) {
        final List<String> assets = merzoxGoldenFontAssets[icon.fontFamily]!;

        for (final String asset in assets) {
          expect(
            File(asset).existsSync(),
            isTrue,
            reason: '${icon.fontFamily} points at a missing $asset',
          );
        }
      }
    });
  });

  group('the bar as a control', () {
    testWidgets('every destination answers, and the button too', (
      WidgetTester tester,
    ) async {
      final List<String> pressed = <String>[];

      await pumpLocalized(
        tester,
        Scaffold(
          bottomNavigationBar: MerzoxNotchedNavBar(
            leading: <MerzoxNavDestination>[
              MerzoxNavDestination(
                glyph: MerzoxIcons.customerNavHome,
                label: 'home',
                selected: true,
                onTap: () => pressed.add('home'),
              ),
              MerzoxNavDestination(
                glyph: MerzoxIcons.customerNavCart,
                label: 'cart',
                selected: false,
                onTap: () => pressed.add('cart'),
              ),
            ],
            trailing: <MerzoxNavDestination>[
              MerzoxNavDestination(
                glyph: MerzoxIcons.customerNavMessages,
                label: 'messages',
                selected: false,
                onTap: () => pressed.add('messages'),
              ),
              MerzoxNavDestination(
                glyph: MerzoxIcons.customerNavProfile,
                label: 'profile',
                selected: false,
                onTap: () => pressed.add('profile'),
              ),
            ],
            buttonGlyph: MerzoxIcons.customerNavStores,
            buttonLabel: 'stores',
            onButtonPressed: () => pressed.add('button'),
          ),
        ),
      );

      for (final String label in <String>[
        'home',
        'cart',
        'messages',
        'profile',
      ]) {
        await tester.tap(find.bySemanticsLabel(label));
        await settleFrames(tester);
      }

      await tester.tap(find.byKey(MerzoxNotchedNavBar.buttonKey));
      await settleFrames(tester);

      expect(pressed, <String>[
        'home',
        'cart',
        'messages',
        'profile',
        'button',
      ]);
    });

    testWidgets('the selected one wears the marker and nobody else does', (
      WidgetTester tester,
    ) async {
      await pumpLocalized(
        tester,
        Scaffold(
          bottomNavigationBar: MerzoxNotchedNavBar(
            leading: <MerzoxNavDestination>[
              MerzoxNavDestination(
                glyph: MerzoxIcons.customerNavHome,
                label: 'home',
                selected: false,
                onTap: () {},
              ),
            ],
            trailing: <MerzoxNavDestination>[
              MerzoxNavDestination(
                glyph: MerzoxIcons.customerNavProfile,
                label: 'profile',
                selected: true,
                onTap: () {},
              ),
            ],
            buttonGlyph: MerzoxIcons.merchantNavAddProduct,
            buttonLabel: 'add',
            onButtonPressed: () {},
          ),
        ),
      );

      final Iterable<MerzoxNavIndicator> markers = tester
          .widgetList<MerzoxNavIndicator>(find.byType(MerzoxNavIndicator));

      expect(markers.where((MerzoxNavIndicator m) => m.selected), hasLength(1));
    });

    testWidgets('a destination can be given something to wear', (
      WidgetTester tester,
    ) async {
      // The waiting-message count, on the one screen that carries it. The bar
      // is handed the badge rather than told about conversations.
      await pumpLocalized(
        tester,
        Scaffold(
          bottomNavigationBar: MerzoxNotchedNavBar(
            leading: <MerzoxNavDestination>[
              MerzoxNavDestination(
                glyph: MerzoxIcons.customerNavHome,
                label: 'home',
                selected: false,
                onTap: () {},
              ),
            ],
            trailing: <MerzoxNavDestination>[
              MerzoxNavDestination(
                glyph: MerzoxIcons.customerNavMessages,
                label: 'messages',
                selected: false,
                onTap: () {},
                decorate: (Widget glyph) => Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    glyph,
                    const Positioned(
                      key: ValueKey<String>('badge'),
                      top: -2,
                      right: -2,
                      child: SizedBox(width: 8, height: 8),
                    ),
                  ],
                ),
              ),
            ],
            buttonGlyph: MerzoxIcons.customerNavStores,
            buttonLabel: 'stores',
            onButtonPressed: () {},
          ),
        ),
      );

      expect(find.byKey(const ValueKey<String>('badge')), findsOneWidget);
    });
  });
}
