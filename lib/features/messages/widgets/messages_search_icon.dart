import 'package:flutter/material.dart';

import '../../../core/constants/colors.dart';

/// The magnifier from `الرسائل`, drawn to the artboard's proportions.
///
/// Material's own is a small circle on a thick stem; the artboard's is a wide
/// thin ring with a short handle, and next to a 3.25 chevron of the same
/// height the difference is the whole character of the bar.
///
/// Measured off `Ellipse_739` and `Line_181`, resolved into the 24-square the
/// icon occupies.
class MessagesSearchIcon extends StatelessWidget {
  final double size;
  final Color color;

  const MessagesSearchIcon({
    super.key,
    this.size = kMessagesSearchBox,
    this.color = MerzoxColors.kColor353535,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: MessagesSearchIconPainter(color: color)),
    );
  }
}

/// The 24-square the artboard gives the mark.
const double kMessagesSearchBox = 24;

/// The ring: its centre line, not its outer edge.
const double kMessagesSearchRingCentre = 12;
const double kMessagesSearchRingRadius = 7.92;
const double kMessagesSearchStroke = 1.38;

/// The handle, leaving the ring at the reading-away corner.
const double kMessagesSearchHandleStart = 17.6;
const double kMessagesSearchHandleEnd = 20.8;

class MessagesSearchIconPainter extends CustomPainter {
  final Color color;

  const MessagesSearchIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.shortestSide / kMessagesSearchBox;
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = kMessagesSearchStroke * scale
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(
      Offset(
        kMessagesSearchRingCentre * scale,
        kMessagesSearchRingCentre * scale,
      ),
      kMessagesSearchRingRadius * scale,
      paint,
    );

    canvas.drawLine(
      Offset(
        kMessagesSearchHandleStart * scale,
        kMessagesSearchHandleStart * scale,
      ),
      Offset(
        kMessagesSearchHandleEnd * scale,
        kMessagesSearchHandleEnd * scale,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(MessagesSearchIconPainter oldDelegate) =>
      oldDelegate.color != color;
}
