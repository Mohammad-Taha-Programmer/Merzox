import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The bar's top edge, with a round bite taken out of its middle.
///
/// Flutter ships one of these already - [CircularNotchedRectangle], the shape
/// [BottomAppBar] uses - and it draws the bite and rounds the two corners
/// where the bite meets the flat edge. What it does not do is let anyone say
/// how round those two corners are: it fixes their curve in cubics chosen for
/// Material's own button. The artboard's corners are wider and softer than
/// that, so the same idea is drawn here out of circles, where the radius is a
/// number somebody can set.
///
/// It is a [NotchedShape] rather than a shape of its own invention, so it can
/// be handed to [BottomAppBar] unchanged if a screen ever wants Flutter to do
/// the hosting.
class MerzoxNotchedShape extends NotchedShape {
  /// How round the two corners are where the flat edge turns into the bite.
  ///
  /// Zero is a sharp corner; larger values pull the turn further out along
  /// the edge and make it gentler.
  final double shoulderRadius;

  const MerzoxNotchedShape({this.shoulderRadius = 16});

  /// The bar, minus the circle the button sits in.
  ///
  /// `guest` is the button's own rectangle already grown by the gap that must
  /// stay between it and the edge - that is the contract [BottomAppBar] calls
  /// this with, and keeping it means the button floats inside the bite
  /// without touching it rather than being press-fitted into it.
  @override
  Path getOuterPath(Rect host, Rect? guest) {
    if (guest == null || guest.width <= 0) {
      return Path()..addRect(host);
    }

    final double r = guest.width / 2;
    final double cx = guest.center.dx;
    final double cy = guest.center.dy;
    final double top = host.top;
    final double s = shoulderRadius;

    // How far below the flat edge the bite's centre lies. Negative is the
    // ordinary case: the button hangs above the bar and only its lower part
    // is bitten out of it.
    final double dy = cy - top;

    // A corner circle of radius `s` sits tangent to the flat edge from below,
    // and tangent to the bite from outside. That fixes how far along the edge
    // its own tangent point falls.
    final double squared = (s + r) * (s + r) - (s - dy) * (s - dy);
    if (squared <= 0) {
      // The bite reaches past where a corner of this size could meet it -
      // there is no edge left to round. A plain rectangle is wrong in a way
      // anybody would see, which is the point: it is a shape nobody should
      // be able to ask for by accident.
      return Path()..addRect(host);
    }

    final double dx = math.sqrt(squared);
    if (cx - dx <= host.left || cx + dx >= host.right) {
      return Path()..addRect(host);
    }

    // Where each corner circle touches the bite. The two circles touch on the
    // line joining their centres, so measured from the bite's centre the
    // meeting point is `r` away along the direction of the corner's centre -
    // which puts it on the lower half of the bite, the half that shows.
    final Offset toCorner = Offset(-dx, s - dy);
    final double span = toCorner.distance;
    final Offset meeting = Offset(cx, cy) + toCorner / span * r;
    final Offset mirrored = Offset(2 * cx - meeting.dx, meeting.dy);

    return Path()
      ..moveTo(host.left, host.top)
      ..lineTo(cx - dx, top)
      // Down off the flat edge, around the near corner.
      ..arcToPoint(meeting, radius: Radius.circular(s), clockwise: true)
      // Around the bottom of the bite, under the button.
      ..arcToPoint(mirrored, radius: Radius.circular(r), clockwise: false)
      // Back up onto the flat edge, around the far corner.
      ..arcToPoint(
        Offset(cx + dx, top),
        radius: Radius.circular(s),
        clockwise: true,
      )
      ..lineTo(host.right, host.top)
      ..lineTo(host.right, host.bottom)
      ..lineTo(host.left, host.bottom)
      ..close();
  }
}
