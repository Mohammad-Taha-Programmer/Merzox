import 'package:flutter/material.dart';

/// Renders the cached average of authoritative business-review documents.
///
/// A business with no reviewers always displays five empty stars, even if a
/// stale legacy average is accidentally present. A real average is rounded
/// only for display to the nearest half-star; the original value remains
/// unchanged in the data model.
class BusinessRatingStars extends StatelessWidget {
  final double rating;
  final int ratingCount;
  final double size;

  const BusinessRatingStars({
    super.key,
    required this.rating,
    required this.ratingCount,
    this.size = 16,
  });

  double get _displayRating {
    if (ratingCount <= 0 || !rating.isFinite) {
      return 0;
    }

    final double clamped = rating.clamp(0, 5).toDouble();

    return (clamped * 2).round() / 2;
  }

  @override
  Widget build(BuildContext context) {
    final double displayRating = _displayRating;

    return Semantics(
      container: true,
      label:
          '${displayRating.toStringAsFixed(1)} out of 5 from $ratingCount ratings',
      child: ExcludeSemantics(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List<Widget>.generate(5, (int index) {
              final double starStart = index.toDouble();

              final IconData icon;
              final Color color;

              if (displayRating >= starStart + 1) {
                icon = Icons.star_rounded;
                color = const Color(0xFFF2CB06);
              } else if (displayRating >= starStart + 0.5) {
                icon = Icons.star_half_rounded;
                color = const Color(0xFFF2CB06);
              } else {
                icon = Icons.star_outline_rounded;
                color = const Color(0xFFD8D8D8);
              }

              return Icon(icon, size: size, color: color);
            }),
          ),
        ),
      ),
    );
  }
}
