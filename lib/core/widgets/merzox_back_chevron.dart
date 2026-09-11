import 'package:flutter/material.dart';

import '../constants/colors.dart';

/// The way back, drawn rather than borrowed.
///
/// The artboards draw a thin two-armed chevron with rounded ends. Material's
/// `BackButton` draws a shafted arrow with a head, which is a different mark
/// entirely - it was the first thing `الرسائل` read as wrong, and the first
/// thing `طلباتي` read as wrong after it.
///
/// The geometry below is measured off `Stroke 3` in the artboard's
/// `Arrow - Right Circle` group, whose own matrix turns a downward chevron a
/// quarter turn so it points along the reading direction. The numbers here are
/// that group already resolved into the 24-square the icon occupies.
class MerzoxBackChevron extends StatelessWidget {
  /// The square the mark is centred in, and the size of the touch target's
  /// artwork. The artboard's is 24.
  final double size;

  final Color color;

  const MerzoxBackChevron({
    super.key,
    this.size = kMerzoxChevronBox,
    this.color = MerzoxColors.kColor707070,
  });

  @override
  Widget build(BuildContext context) {
    // The chevron points the way back, which in Arabic is towards the right
    // edge and in English towards the left. One drawing, mirrored, rather than
    // two icons that could drift apart.
    final bool rightward = Directionality.of(context) == TextDirection.rtl;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: MerzoxBackChevronPainter(color: color, rightward: rightward),
      ),
    );
  }
}

/// The 24-square the artboard gives the mark.
const double kMerzoxChevronBox = 24;

/// Where the arms end, as measured in that square.
const double kMerzoxChevronArmX = 8.65;
const double kMerzoxChevronTopY = 4.6;
const double kMerzoxChevronBottomY = 19.4;

/// Where the point sits.
const double kMerzoxChevronTipX = 16;
const double kMerzoxChevronTipY = 12;

/// The stroke, derived from the filled outline: the artboard stores the mark
/// as a shape, and the width is twice the distance from the centre line to it.
const double kMerzoxChevronStroke = 3.25;

/// The tap target around the mark, which is larger than the mark so a thin
/// drawing is still something a thumb can hit.
const double kMerzoxChevronTouchTarget = 40;

class MerzoxBackChevronPainter extends CustomPainter {
  final Color color;

  /// Whether the point faces the right edge, as it does in a right-to-left
  /// reading order.
  final bool rightward;

  const MerzoxBackChevronPainter({
    required this.color,
    required this.rightward,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.shortestSide / kMerzoxChevronBox;

    double x(double value) {
      final double scaled = value * scale;
      return rightward ? scaled : size.width - scaled;
    }

    final Path path = Path()
      ..moveTo(x(kMerzoxChevronArmX), kMerzoxChevronTopY * scale)
      ..lineTo(x(kMerzoxChevronTipX), kMerzoxChevronTipY * scale)
      ..lineTo(x(kMerzoxChevronArmX), kMerzoxChevronBottomY * scale);

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = kMerzoxChevronStroke * scale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(MerzoxBackChevronPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.rightward != rightward;
}

/// The mark with a tap target around it, and a name a screen reader can say.
///
/// Every board that carries a way back wants the same three things - the mark,
/// something large enough to press, and a label - so they are kept together
/// rather than rebuilt per screen.
class MerzoxBackChevronButton extends StatelessWidget {
  final VoidCallback onTap;
  final String semanticsLabel;
  final Key? valueKey;
  final Color color;
  final double size;
  final double touchTarget;

  const MerzoxBackChevronButton({
    super.key,
    required this.onTap,
    required this.semanticsLabel,
    this.valueKey,
    this.color = MerzoxColors.kColor707070,
    this.size = kMerzoxChevronBox,
    this.touchTarget = kMerzoxChevronTouchTarget,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: InkWell(
        key: valueKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(touchTarget / 2),
        child: SizedBox(
          width: touchTarget,
          height: touchTarget,
          child: Center(
            child: MerzoxBackChevron(size: size, color: color),
          ),
        ),
      ),
    );
  }
}
