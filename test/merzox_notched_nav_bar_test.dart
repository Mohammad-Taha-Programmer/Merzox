import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/widgets/merzox_nav_icons.dart';
import 'package:merzox/core/widgets/merzox_notched_nav_bar.dart';
import 'package:merzox/core/widgets/merzox_notched_shape.dart';

import 'localization_test_harness.dart';

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
      const Offset probe = Offset(
        _centre - 36,
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
    test('every one is drawn, and stays on its grid', () {
      for (final MerzoxNavGlyph glyph in MerzoxNavGlyph.values) {
        final Path path = pathFor(glyph);
        final Rect bounds = path.getBounds();

        expect(bounds.isEmpty, isFalse, reason: '$glyph drew nothing');
        // Inside the 24-unit box they are all written on. One glyph drawn on
        // a different grid is one glyph a size heavier than its neighbours,
        // which is the whole of what makes a set look borrowed.
        expect(bounds.left, greaterThanOrEqualTo(0), reason: '$glyph');
        expect(bounds.top, greaterThanOrEqualTo(0), reason: '$glyph');
        expect(bounds.right, lessThanOrEqualTo(24), reason: '$glyph');
        expect(bounds.bottom, lessThanOrEqualTo(24), reason: '$glyph');
      }
    });

    test('and each one is its own drawing', () {
      // A switch that fell through would give two destinations the same
      // picture, which is the kind of thing a golden of a whole screen hides.
      final Set<String> seen = <String>{};

      for (final MerzoxNavGlyph glyph in MerzoxNavGlyph.values) {
        final Rect bounds = pathFor(glyph).getBounds();
        expect(
          seen.add('${bounds.left},${bounds.top},${bounds.right},${bounds.bottom}'),
          isTrue,
          reason: '$glyph is drawn exactly like another glyph',
        );
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
                glyph: MerzoxNavGlyph.home,
                label: 'home',
                selected: true,
                onTap: () => pressed.add('home'),
              ),
              MerzoxNavDestination(
                glyph: MerzoxNavGlyph.cart,
                label: 'cart',
                selected: false,
                onTap: () => pressed.add('cart'),
              ),
            ],
            trailing: <MerzoxNavDestination>[
              MerzoxNavDestination(
                glyph: MerzoxNavGlyph.messages,
                label: 'messages',
                selected: false,
                onTap: () => pressed.add('messages'),
              ),
              MerzoxNavDestination(
                glyph: MerzoxNavGlyph.profile,
                label: 'profile',
                selected: false,
                onTap: () => pressed.add('profile'),
              ),
            ],
            buttonGlyph: MerzoxNavGlyph.storefront,
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
                glyph: MerzoxNavGlyph.home,
                label: 'home',
                selected: false,
                onTap: () {},
              ),
            ],
            trailing: <MerzoxNavDestination>[
              MerzoxNavDestination(
                glyph: MerzoxNavGlyph.profile,
                label: 'profile',
                selected: true,
                onTap: () {},
              ),
            ],
            buttonGlyph: MerzoxNavGlyph.add,
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
                glyph: MerzoxNavGlyph.home,
                label: 'home',
                selected: false,
                onTap: () {},
              ),
            ],
            trailing: <MerzoxNavDestination>[
              MerzoxNavDestination(
                glyph: MerzoxNavGlyph.messages,
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
            buttonGlyph: MerzoxNavGlyph.storefront,
            buttonLabel: 'stores',
            onButtonPressed: () {},
          ),
        ),
      );

      expect(find.byKey(const ValueKey<String>('badge')), findsOneWidget);
    });
  });
}
