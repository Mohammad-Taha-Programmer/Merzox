import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The corner banner on a shop that is running offers.
///
/// Measured off `Path 36712` on the `الرئيسية` board rather than guessed. The
/// board draws a band of `#e40909` cutting the card's leading top corner: its
/// long axis is turned fifty degrees off the horizontal, it is fourteen
/// across, and its centre line crosses the top edge about thirty-five in from
/// the corner and the leading edge about forty-one down. The band is drawn
/// past both edges and the card's own rounded clip trims it, which is what
/// gives the ends their mitre.
class DiscountRibbon extends StatelessWidget {
  final String label;

  const DiscountRibbon({required this.label, super.key});

  /// Visible for the test that holds this against the board.
  static const double thickness = 14;

  /// Where the band's centre sits, measured from the card's leading top
  /// corner: the midpoint between its two edge crossings.
  static const double centreX = 17.5;
  static const double centreY = 20.5;

  /// Long enough to run past both edges from that centre - the nearer
  /// crossing is only twenty-seven away - so the card trims it, not this.
  static const double _length = 90;

  static const double turn = 50 * math.pi / 180;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // A frame for the corner, not a bound: the band deliberately runs out of
      // it on both ends.
      width: centreX * 2,
      height: centreY * 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(
            left: centreX - _length / 2,
            top: centreY - thickness / 2,
            width: _length,
            height: thickness,
            child: Transform.rotate(
              angle: -turn,
              child: Container(
                alignment: Alignment.center,
                color: const Color(0xFFE40909),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    letterSpacing: 0.16,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
