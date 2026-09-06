import 'package:flutter/material.dart';

import '../../../core/constants/colors.dart';

/// The back control from `الرسائل`, drawn rather than borrowed.
///
/// The artboard's is a thin two-armed chevron with rounded ends. Material's
/// `BackButton` draws a shafted arrow with a head, which is a different mark
/// entirely - it was the first thing the design read as wrong.
///
/// The geometry below is measured off `Stroke 3` in the artboard's
/// `Arrow - Right Circle` group, whose own matrix turns a downward chevron a
/// quarter turn so it points along the reading direction. The numbers here are
/// that group already resolved into the 24-square the icon occupies.
class MessagesBackChevron extends StatelessWidget {
  /// The square the mark is centred in, and the size of the touch target's
  /// artwork. The artboard's is 24.
  final double size;

  final Color color;

  const MessagesBackChevron({
    super.key,
    this.size = kMessagesChevronBox,
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
        painter: MessagesBackChevronPainter(color: color, rightward: rightward),
      ),
    );
  }
}

/// The 24-square the artboard gives the mark.
const double kMessagesChevronBox = 24;

/// Where the arms end, as measured in that square.
const double kMessagesChevronArmX = 8.65;
const double kMessagesChevronTopY = 4.6;
const double kMessagesChevronBottomY = 19.4;

/// Where the point sits.
const double kMessagesChevronTipX = 16;
const double kMessagesChevronTipY = 12;

/// The stroke, derived from the filled outline: the artboard stores the mark
/// as a shape, and the width is twice the distance from the centre line to it.
const double kMessagesChevronStroke = 3.25;

class MessagesBackChevronPainter extends CustomPainter {
  final Color color;

  /// Whether the point faces the right edge, as it does in a right-to-left
  /// reading order.
  final bool rightward;

  const MessagesBackChevronPainter({
    required this.color,
    required this.rightward,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.shortestSide / kMessagesChevronBox;

    double x(double value) {
      final double scaled = value * scale;
      return rightward ? scaled : size.width - scaled;
    }

    final Path path = Path()
      ..moveTo(x(kMessagesChevronArmX), kMessagesChevronTopY * scale)
      ..lineTo(x(kMessagesChevronTipX), kMessagesChevronTipY * scale)
      ..lineTo(x(kMessagesChevronArmX), kMessagesChevronBottomY * scale);

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = kMessagesChevronStroke * scale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(MessagesBackChevronPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.rightward != rightward;
}
