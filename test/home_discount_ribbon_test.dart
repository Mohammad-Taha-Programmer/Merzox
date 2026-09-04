import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/home/widgets/discount_ribbon.dart';

/// The offers banner, held against the numbers on the `الرئيسية` board.
///
/// The band was previously an orange pill in the card's margin, which is not
/// what the board draws, and the first two attempts at the banner were eyeballed
/// and wrong - one turned it forty degrees instead of fifty, the other let a
/// parent's constraints crop it into a floating stick. So this measures the
/// rendered pixels rather than reading the source: where the red actually meets
/// each edge of the card is the only thing that can be compared to the board.

const Key _card = Key('card');

/// `Rectangle 17349`: the shop card the banner sits on.
const double _cardWidth = 164;
const double _cardHeight = 208;
const double _cardRadius = 5;

/// Where `Path 36712` crosses the card's edges, measured from the corner.
const double _xdTopFrom = 26;
const double _xdTopTo = 44;
const double _xdLeadingFrom = 30;
const double _xdLeadingTo = 52;

Future<List<List<bool>>> _redMask(WidgetTester tester) async {
  final RenderRepaintBoundary boundary =
      tester.renderObject(find.byKey(_card)) as RenderRepaintBoundary;

  late final ByteData bytes;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage();
    bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();
  });

  final int width = _cardWidth.round();
  final int height = _cardHeight.round();

  return <List<bool>>[
    for (int y = 0; y < height; y++)
      <bool>[
        for (int x = 0; x < width; x++)
          () {
            final int i = (y * width + x) * 4;
            return bytes.getUint8(i) > 180 &&
                bytes.getUint8(i + 1) < 70 &&
                bytes.getUint8(i + 2) < 70;
          }(),
      ],
  ];
}

/// The first and last index that is set, or null when none is.
(int, int)? _run(List<bool> line) {
  final int first = line.indexOf(true);
  if (first < 0) return null;
  return (first, line.lastIndexOf(true));
}

Widget _cardWithRibbon(String label) {
  return Directionality(
    textDirection: TextDirection.rtl,
    child: Center(
      child: RepaintBoundary(
        key: _card,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_cardRadius),
          child: SizedBox(
            width: _cardWidth,
            height: _cardHeight,
            child: Stack(
              children: <Widget>[
                const ColoredBox(color: Colors.white, child: SizedBox.expand()),
                PositionedDirectional(
                  top: 0,
                  end: 0,
                  child: DiscountRibbon(label: label),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('the band cuts the corner where the board cuts it', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_cardWithRibbon('50%'));
    await tester.pumpAndSettle();

    final List<List<bool>> red = await _redMask(tester);

    // The card's own clip rounds the very corner away, so allow the crossings
    // to sit a couple of pixels in from where the board puts them.
    final (int, int)? top = _run(red.first);
    expect(top, isNotNull, reason: 'the band must reach the card top edge');
    expect((top!.$1 - _xdTopFrom).abs(), lessThanOrEqualTo(3));
    expect((top.$2 - _xdTopTo).abs(), lessThanOrEqualTo(3));

    final (int, int)? leading = _run(<bool>[
      for (final List<bool> row in red) row.first,
    ]);
    expect(leading, isNotNull, reason: 'the band must reach the leading edge');
    expect((leading!.$1 - _xdLeadingFrom).abs(), lessThanOrEqualTo(3));
    expect((leading.$2 - _xdLeadingTo).abs(), lessThanOrEqualTo(3));
  });

  testWidgets('it is a band across the corner, not a pill in the margin', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_cardWithRibbon('50%'));
    await tester.pumpAndSettle();

    final List<List<bool>> red = await _redMask(tester);

    // A band leaves both edges it crosses and nothing else. The old pill sat
    // clear of the edges entirely, and the cropped stick reached neither.
    final int lowest = red.lastIndexWhere(
      (List<bool> row) => row.contains(true),
    );
    expect(
      lowest,
      lessThan(_cardHeight / 2),
      reason: 'the band belongs to the corner, not the body of the card',
    );

    final int widest = red
        .map((List<bool> row) => row.where((bool on) => on).length)
        .reduce((int a, int b) => a > b ? a : b);
    expect(
      widest,
      lessThan(_cardWidth / 2),
      reason: 'no row of the card is more than half banner',
    );
  });

  testWidgets('a long label does not stretch or wrap the band', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_cardWithRibbon('عروض حتى 90 بالمئة على كل شيء'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    final List<List<bool>> red = await _redMask(tester);
    final (int, int)? top = _run(red.first);

    expect(top, isNotNull);
    expect(
      top!.$2 - top.$1 + 1,
      closeTo(_xdTopTo - _xdTopFrom + 1, 3),
      reason: 'the band keeps its width whatever the label says',
    );
  });
}
