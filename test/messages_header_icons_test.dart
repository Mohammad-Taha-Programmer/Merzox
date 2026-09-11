import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/widgets/merzox_back_chevron.dart';
import 'package:merzox/core/widgets/merzox_icons.dart';

/// The two marks in the inbox bar.
///
/// The back control was the first thing the design read as wrong: Material's
/// `BackButton` draws a shafted arrow with a head, and the artboard's is a
/// bare two-armed chevron. They are different marks, not different weights of
/// the same one, so this draws the artboard's rather than dressing up
/// Material's.
///
/// The numbers asserted here are the artboard's own, resolved into the
/// 24-square each icon occupies. A test that only checked "something painted"
/// would have passed for the arrow that was already there.

/// Records what a painter asked the canvas to draw.
class _Recorder implements Canvas {
  final List<Path> paths = <Path>[];
  final List<({Offset centre, double radius})> circles =
      <({Offset centre, double radius})>[];
  final List<({Offset from, Offset to})> lines = <({Offset from, Offset to})>[];
  final List<Paint> paints = <Paint>[];

  @override
  void drawPath(Path path, Paint paint) {
    paths.add(path);
    paints.add(paint);
  }

  @override
  void drawCircle(Offset c, double radius, Paint paint) {
    circles.add((centre: c, radius: radius));
    paints.add(paint);
  }

  @override
  void drawLine(Offset from, Offset to, Paint paint) {
    lines.add((from: from, to: to));
    paints.add(paint);
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

_Recorder _paintChevron({required bool rightward, double box = 24}) {
  final _Recorder canvas = _Recorder();
  MerzoxBackChevronPainter(
    color: const Color(0xFF707070),
    rightward: rightward,
  ).paint(canvas, Size(box, box));
  return canvas;
}

void main() {
  test('the chevron is a stroke, not a filled arrowhead', () {
    final _Recorder canvas = _paintChevron(rightward: true);

    expect(canvas.paths.length, 1);
    expect(canvas.paints.single.style, PaintingStyle.stroke);
    // Round ends and a round elbow: the artboard's caps, and what separates a
    // drawn chevron from a mitred one.
    expect(canvas.paints.single.strokeCap, StrokeCap.round);
    expect(canvas.paints.single.strokeJoin, StrokeJoin.round);
    expect(
      canvas.paints.single.strokeWidth,
      closeTo(kMerzoxChevronStroke, 0.001),
    );
  });

  test('it points towards the right edge when reading right to left', () {
    final Rect drawn = _paintChevron(rightward: true).paths.single.getBounds();

    // The point is the far side of the mark from its arms.
    expect(drawn.right, closeTo(kMerzoxChevronTipX, 0.01));
    expect(drawn.left, closeTo(kMerzoxChevronArmX, 0.01));
  });

  test('it mirrors for a left-to-right reader rather than pointing away', () {
    final Rect drawn = _paintChevron(rightward: false).paths.single.getBounds();

    // Mirrored about the 24-square: the arms are now on the right.
    expect(drawn.left, closeTo(kMerzoxChevronBox - kMerzoxChevronTipX, 0.01));
    expect(drawn.right, closeTo(kMerzoxChevronBox - kMerzoxChevronArmX, 0.01));
  });

  test('its arms reach the artboard height, and it stays in its square', () {
    final Rect drawn = _paintChevron(rightward: true).paths.single.getBounds();

    expect(drawn.top, closeTo(kMerzoxChevronTopY, 0.01));
    expect(drawn.bottom, closeTo(kMerzoxChevronBottomY, 0.01));
    expect(drawn.height, closeTo(14.8, 0.01));
  });

  test('it scales with the square it is given', () {
    final Rect drawn = _paintChevron(
      rightward: true,
      box: 48,
    ).paths.single.getBounds();

    expect(drawn.height, closeTo(14.8 * 2, 0.02));
  });

  testWidgets('the direction is read from the text direction, not passed in', (
    WidgetTester tester,
  ) async {
    for (final TextDirection direction in TextDirection.values) {
      await tester.pumpWidget(
        Directionality(
          textDirection: direction,
          child: const Center(child: MerzoxBackChevron()),
        ),
      );

      final MerzoxBackChevronPainter painter =
          tester
                  .widget<CustomPaint>(
                    find.descendant(
                      of: find.byType(MerzoxBackChevron),
                      matching: find.byType(CustomPaint),
                    ),
                  )
                  .painter!
              as MerzoxBackChevronPainter;

      expect(painter.rightward, direction == TextDirection.rtl);
    }
  });

  test('the magnifier is the shared one, at the chevron\'s own height', () {
    // What used to be held here was the geometry of a drawn ring: its radius,
    // its stroke, where the handle left the rim. The mark comes from the
    // designer's font now, so the question that remains is whether this bar
    // draws the same magnifier every other field draws, at a size that stands
    // beside the chevron rather than over or under it.
    //
    // Both marks are given the artboard's 24-square. The chevron fills it and
    // the magnifier's glyph fills its own em box, so the magnifier's font size
    // is 24 converted - and the two come out the same height, which is the
    // whole reason the drawn one existed.
    expect(MerzoxIcons.messagesHeaderSearch.fontFamily, 'MessagesHeaderSearch');
    expect(
      24 * MerzoxIcons.searchSizeFactor,
      closeTo(24 * 0.711, 0.001),
      reason: 'the conversion is the one measured against Material',
    );
    expect(
      kMerzoxChevronBox,
      24,
      reason: 'both marks are drawn on the same square',
    );
  });
}
