import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/widgets/merzox_back_chevron.dart';
import 'package:merzox/features/messages/widgets/messages_search_icon.dart';

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
    expect(
      drawn.left,
      closeTo(kMerzoxChevronBox - kMerzoxChevronTipX, 0.01),
    );
    expect(
      drawn.right,
      closeTo(kMerzoxChevronBox - kMerzoxChevronArmX, 0.01),
    );
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

  test('the magnifier is a thin ring with a handle on the outside', () {
    final _Recorder canvas = _Recorder();
    const MessagesSearchIconPainter(
      color: Color(0xFF353535),
    ).paint(canvas, const Size(24, 24));

    expect(
      canvas.circles.single.radius,
      closeTo(kMessagesSearchRingRadius, 0.001),
    );
    expect(canvas.circles.single.centre.dx, kMessagesSearchRingCentre);
    expect(canvas.paints.first.style, PaintingStyle.stroke);
    expect(
      canvas.paints.first.strokeWidth,
      closeTo(kMessagesSearchStroke, 0.001),
    );

    // The handle leaves the ring rather than crossing it: its near end sits on
    // the rim, not inside the glass.
    final double rim =
        kMessagesSearchRingCentre + kMessagesSearchRingRadius * 0.7071;
    expect(canvas.lines.single.from.dx, closeTo(rim, 0.05));
    expect(canvas.lines.single.to.dx, greaterThan(canvas.lines.single.from.dx));
  });

  test('the whole magnifier stays inside its square', () {
    const double outer =
        kMessagesSearchRingCentre +
        kMessagesSearchRingRadius +
        kMessagesSearchStroke / 2;

    expect(outer, lessThanOrEqualTo(kMessagesSearchBox));
    expect(
      kMessagesSearchHandleEnd + kMessagesSearchStroke / 2,
      lessThanOrEqualTo(kMessagesSearchBox),
    );
  });
}
