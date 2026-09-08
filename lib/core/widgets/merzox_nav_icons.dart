import 'package:flutter/material.dart';

/// The glyphs the bottom bars draw.
///
/// Material's own set was standing in for these and reads as a different
/// drawing hand: heavier, rounder, and each one a different weight from the
/// next because they were picked one at a time. The artboard's are one family
/// - a single stroke width, square ends softened, everything built on the
/// same grid - so they are drawn here rather than borrowed.
///
/// Paths, not pictures. The project carries no SVG reader and no icon font,
/// and adding either for eight glyphs would be a dependency and a binary to
/// keep in step with a design file. A path scales to any size, takes its
/// colour from the caller, and can be read in a diff.
enum MerzoxNavGlyph { home, orders, products, profile, cart, messages, storefront, add }

/// One glyph, stroked.
///
/// Every path is written on a 24-unit grid and scaled to [size], so the
/// strokes stay the same weight relative to each other whatever size a bar
/// asks for - which is the half of "one family" that a shared stroke width
/// alone does not buy.
class MerzoxNavIcon extends StatelessWidget {
  final MerzoxNavGlyph glyph;
  final double size;
  final Color color;

  /// Stroke weight on the 24-unit grid, before scaling.
  final double weight;

  const MerzoxNavIcon({
    super.key,
    required this.glyph,
    required this.color,
    this.size = 24,
    this.weight = 1.7,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GlyphPainter(glyph: glyph, color: color, weight: weight),
        // The glyph is the whole of it, so the name belongs to whatever draws
        // this - a bar item that already carries its own label.
        isComplex: false,
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  final MerzoxNavGlyph glyph;
  final Color color;
  final double weight;

  const _GlyphPainter({
    required this.glyph,
    required this.color,
    required this.weight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.width / 24;

    canvas
      ..save()
      ..scale(scale);

    canvas.drawPath(
      pathFor(glyph),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = color
        ..strokeWidth = weight
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.color != color || old.weight != weight;
}

/// The glyph itself, on the 24-unit grid.
///
/// Pulled out of the painter so a test can measure a path rather than a
/// picture: what matters about these is that each one stays inside the grid
/// and none of them is empty, and both are questions about geometry.
@visibleForTesting
Path pathFor(MerzoxNavGlyph glyph) {
  switch (glyph) {
    case MerzoxNavGlyph.home:
      return Path()
        ..moveTo(3.4, 10.4)
        ..lineTo(12, 3.6)
        ..lineTo(20.6, 10.4)
        ..moveTo(5.5, 8.8)
        ..lineTo(5.5, 20)
        ..lineTo(18.5, 20)
        ..lineTo(18.5, 8.8)
        ..moveTo(9.7, 20)
        ..lineTo(9.7, 14.2)
        ..lineTo(14.3, 14.2)
        ..lineTo(14.3, 20);

    case MerzoxNavGlyph.orders:
      return Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(5.4, 3.2, 18.6, 20.8),
            const Radius.circular(2.6),
          ),
        )
        ..moveTo(8.7, 8.6)
        ..lineTo(15.3, 8.6)
        ..moveTo(8.7, 12)
        ..lineTo(15.3, 12)
        ..moveTo(8.7, 15.4)
        ..lineTo(13, 15.4);

    case MerzoxNavGlyph.products:
      // A box seen a little from above: the lid's two edges meet the front
      // seam in the middle, which is what makes it read as a box rather than
      // as a hexagon.
      return Path()
        ..moveTo(12, 3.6)
        ..lineTo(20.2, 8)
        ..lineTo(20.2, 16.6)
        ..lineTo(12, 21)
        ..lineTo(3.8, 16.6)
        ..lineTo(3.8, 8)
        ..close()
        ..moveTo(3.8, 8)
        ..lineTo(12, 12.4)
        ..lineTo(20.2, 8)
        ..moveTo(12, 12.4)
        ..lineTo(12, 21);

    case MerzoxNavGlyph.profile:
      return Path()
        ..addOval(
          Rect.fromCircle(center: const Offset(12, 8.4), radius: 3.7),
        )
        ..moveTo(4.9, 20.2)
        ..cubicTo(4.9, 16.3, 8.1, 14.3, 12, 14.3)
        ..cubicTo(15.9, 14.3, 19.1, 16.3, 19.1, 20.2);

    case MerzoxNavGlyph.cart:
      return Path()
        ..moveTo(9, 10.2)
        ..lineTo(9, 7.4)
        ..cubicTo(9, 5.7, 10.3, 4.4, 12, 4.4)
        ..cubicTo(13.7, 4.4, 15, 5.7, 15, 7.4)
        ..lineTo(15, 10.2)
        ..addRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(4.8, 7.8, 19.2, 20.6),
            const Radius.circular(2.6),
          ),
        );

    case MerzoxNavGlyph.messages:
      return Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(3.6, 4.6, 20.4, 16.6),
            const Radius.circular(3.2),
          ),
        )
        ..moveTo(8.8, 16.6)
        ..lineTo(8.8, 20.6)
        ..lineTo(13.2, 16.6);

    case MerzoxNavGlyph.storefront:
      return Path()
        ..moveTo(3.6, 4.6)
        ..lineTo(20.4, 4.6)
        ..lineTo(21.6, 9.4)
        ..lineTo(2.4, 9.4)
        ..close()
        ..moveTo(4.6, 9.4)
        ..lineTo(4.6, 20)
        ..moveTo(19.4, 9.4)
        ..lineTo(19.4, 20)
        ..moveTo(4.6, 20)
        ..lineTo(19.4, 20)
        ..moveTo(9.6, 20)
        ..lineTo(9.6, 14)
        ..lineTo(14.4, 14)
        ..lineTo(14.4, 20);

    case MerzoxNavGlyph.add:
      // The raised button's own glyph: a rounded square with a cross in it,
      // which is the artboard's, and not Material's bare `+`.
      return Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(4.4, 4.4, 19.6, 19.6),
            const Radius.circular(4.4),
          ),
        )
        ..moveTo(12, 8.8)
        ..lineTo(12, 15.2)
        ..moveTo(8.8, 12)
        ..lineTo(15.2, 12);
  }
}
