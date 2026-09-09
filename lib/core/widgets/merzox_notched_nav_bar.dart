import 'package:flutter/material.dart';

import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/core/widgets/merzox_notched_shape.dart';

/// The active-tab marker every Merzox bottom bar draws.
///
/// Measured from the artboards, not chosen here: a 24x2 bar sitting above the
/// icon, never a disc behind it.
const double kMerzoxNavIndicatorWidth = 24;
const double kMerzoxNavIndicatorHeight = 2;
const double kMerzoxNavIndicatorGap = 13;

/// The bar's own height, below its top edge.
const double kMerzoxNavBarHeight = 62;

/// The raised button, and the room kept around it.
const double kMerzoxNavButtonDiameter = 56;

/// The mark on each of the bar's own places, as a font size.
///
/// The ink of these glyphs fills its em box, so this is the mark's height too.
const double kMerzoxNavItemGlyphSize = 23;

/// The mark inside the raised button, as a font size.
///
/// The ink of every one of these glyphs fills its em box top to bottom, so
/// this is also the mark's height: a little under two fifths of the button,
/// which leaves the orange reading as a disc the mark sits in rather than as
/// a ring around a mark that has outgrown it.
const double kMerzoxNavButtonGlyphSize = 22;

/// How far the bite is cut past the button on every side. This is the gap the
/// artboard shows: the button floats in the bite rather than filling it.
const double kMerzoxNavButtonGap = 6;

/// How far above the bar's top edge the button's centre sits.
const double kMerzoxNavButtonLift = 8;

/// The radius of the bite itself.
const double kMerzoxNavNotchRadius =
    kMerzoxNavButtonDiameter / 2 + kMerzoxNavButtonGap;

/// How far the button stands proud of the bar.
const double kMerzoxNavOverhang =
    kMerzoxNavButtonLift + kMerzoxNavButtonDiameter / 2;

/// The whole control's height, button included.
const double kMerzoxNavBarTotalHeight =
    kMerzoxNavBarHeight + kMerzoxNavOverhang;

/// The marker itself, so the bars cannot render it differently.
class MerzoxNavIndicator extends StatelessWidget {
  final bool selected;

  const MerzoxNavIndicator({super.key, required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: kMerzoxNavIndicatorWidth,
      height: kMerzoxNavIndicatorHeight,
      decoration: BoxDecoration(
        color: selected ? MerzoxColors.kColorEE6C4D : Colors.transparent,
        borderRadius: BorderRadius.circular(kMerzoxNavIndicatorHeight),
      ),
    );
  }
}

/// One place a bar can send you.
class MerzoxNavDestination {
  final IconData glyph;

  /// Read out loud. Nothing draws it: the artboards label none of these.
  final String label;

  final bool selected;
  final VoidCallback onTap;

  /// Wraps the glyph in whatever the caller hangs on it - the waiting-message
  /// count, so far. It is a function rather than a flag because the bar has
  /// no business knowing what a conversation is.
  final Widget Function(Widget glyph)? decorate;

  const MerzoxNavDestination({
    required this.glyph,
    required this.label,
    required this.selected,
    required this.onTap,
    this.decorate,
  });
}

/// The bottom bar, with a round bite in its top edge and a button floating in
/// it.
///
/// Four copies of this existed - the home screen's, the storefront's, the
/// shared customer one and the merchant's - and each faked the bite the same
/// way: a white circle laid over the bar, or a white ring drawn round the
/// button. Both tricks need the thing behind the bar to be white too, and
/// neither draws the artboard's shape, whose bite has softly turned corners
/// where it meets the flat edge.
///
/// This cuts the bite out of the bar instead, through [MerzoxNotchedShape],
/// so what is behind shows through it - which is what makes the gap around
/// the button a gap rather than a painted circle.
class MerzoxNotchedNavBar extends StatelessWidget {
  /// The destinations before the bite, in reading order.
  final List<MerzoxNavDestination> leading;

  /// And after it.
  final List<MerzoxNavDestination> trailing;

  /// The raised button's glyph, what it is called, and what it does.
  final IconData buttonGlyph;
  final String buttonLabel;
  final bool buttonSelected;
  final VoidCallback onButtonPressed;

  /// Names the raised button for a test.
  ///
  /// It was needed when the glyph was a hand-drawn path nothing could search
  /// for. The glyph is an [IconData] now and `find.byIcon` would reach it, but
  /// the key says *which button* rather than which picture is on it, and the
  /// picture is the half that changes.
  static const ValueKey<String> buttonKey = ValueKey<String>('merzoxNav.button');

  const MerzoxNotchedNavBar({
    super.key,
    required this.leading,
    required this.trailing,
    required this.buttonGlyph,
    required this.buttonLabel,
    required this.onButtonPressed,
    this.buttonSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: kMerzoxNavBarTotalHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned.fill(
              child: CustomPaint(
                painter: const _NotchedBarPainter(),
                // The bar is a surface, not a control: everything you can
                // press sits on top of it.
                isComplex: false,
              ),
            ),
            Positioned(
              top: kMerzoxNavOverhang,
              left: 0,
              right: 0,
              height: kMerzoxNavBarHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: <Widget>[
                    for (final MerzoxNavDestination item in leading)
                      Expanded(child: _NavItem(destination: item)),
                    // The bite's full width, so no destination is ever drawn
                    // under the button.
                    const SizedBox(width: kMerzoxNavNotchRadius * 2),
                    for (final MerzoxNavDestination item in trailing)
                      Expanded(child: _NavItem(destination: item)),
                  ],
                ),
              ),
            ),
            Positioned(
              top: kMerzoxNavOverhang -
                  kMerzoxNavButtonLift -
                  kMerzoxNavButtonDiameter / 2,
              left: 0,
              right: 0,
              child: Center(
                child: MerzoxNavRaisedButton(
                  glyph: buttonGlyph,
                  label: buttonLabel,
                  selected: buttonSelected,
                  onPressed: onButtonPressed,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The button that floats in the bite.
///
/// It carries no white ring. The ring existed to fake the gap the bar now
/// actually has, and on anything but a white background it read as a white
/// ring - which is what it was.
class MerzoxNavRaisedButton extends StatelessWidget {
  final IconData glyph;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  const MerzoxNavRaisedButton({
    super.key,
    required this.glyph,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkResponse(
        key: MerzoxNotchedNavBar.buttonKey,
        onTap: onPressed,
        radius: kMerzoxNavButtonDiameter / 2,
        customBorder: const CircleBorder(),
        child: Container(
          width: kMerzoxNavButtonDiameter,
          height: kMerzoxNavButtonDiameter,
          decoration: BoxDecoration(
            color: MerzoxColors.kColorEE6C4D,
            shape: BoxShape.circle,
            // Pushed down and kept tight on purpose. The gap around the
            // button is only [kMerzoxNavButtonGap] wide, and a shadow blurred
            // further than it is offset spills up into that gap and fills it
            // with orange haze - which reads as a bad edge rather than as a
            // shadow, and undoes the thing the gap is there to show.
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: MerzoxColors.kColorEE6C4D.withValues(alpha: 0.30),
                blurRadius: 8,
                // Pulled in by more than the blur pushes out, so the haze
                // reaches 4px to the side of a 6px gap and no distance at all
                // above the button. What is left is a shadow under it.
                spreadRadius: -4,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Center(child: _RaisedButtonGlyph(glyph: glyph)),
        ),
      ),
    );
  }
}

/// The mark inside the raised button.
///
/// Drawn as text rather than with [Icon], which clamps its glyph into a
/// `size`-by-`size` box. One of these two - the customer's shop awning - has
/// an advance of 1.25em, so it did not fit that box, and the paragraph laid
/// what would not fit against the reading edge instead. The mark ended up
/// 3.3px off the button's centre, half its own overflow, and no amount of
/// centring outside [Icon] could reach the clamp inside it.
///
/// With nothing narrower than the button constraining it, the glyph lays out
/// at its own advance and that is what gets centred - which is what centred
/// means for a mark that is wider than it is tall.
class _RaisedButtonGlyph extends StatelessWidget {
  final IconData glyph;

  const _RaisedButtonGlyph({required this.glyph});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Text(
        String.fromCharCode(glyph.codePoint),
        softWrap: false,
        style: TextStyle(
          fontFamily: glyph.fontFamily,
          fontSize: kMerzoxNavButtonGlyphSize,
          // The ink fills the em box top to bottom in every one of these
          // fonts, so a line box of exactly the font size is the glyph and
          // nothing else - which is what makes the vertical centring exact.
          height: 1,
          leadingDistribution: TextLeadingDistribution.even,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final MerzoxNavDestination destination;

  const _NavItem({required this.destination});

  Widget _decorated(Widget glyph) =>
      destination.decorate?.call(glyph) ?? glyph;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: destination.label,
      button: true,
      selected: destination.selected,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: destination.onTap,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              MerzoxNavIndicator(selected: destination.selected),
              const SizedBox(height: kMerzoxNavIndicatorGap),
              _decorated(
                Icon(
                  destination.glyph,
                  size: kMerzoxNavItemGlyphSize,
                  color: destination.selected
                      ? MerzoxColors.kColorEE6C4D
                      : MerzoxColors.kColor8D99AE,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotchedBarPainter extends CustomPainter {
  const _NotchedBarPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Rect host = Rect.fromLTRB(
      0,
      kMerzoxNavOverhang,
      size.width,
      size.height,
    );
    final Rect notch = Rect.fromCircle(
      center: Offset(
        size.width / 2,
        kMerzoxNavOverhang - kMerzoxNavButtonLift,
      ),
      radius: kMerzoxNavNotchRadius,
    );

    final Path path = const MerzoxNotchedShape().getOuterPath(host, notch);

    // Drawn from the shape itself rather than as a rectangle's box shadow, so
    // the shadow follows the bite instead of running straight across it.
    canvas
      ..drawPath(
        path,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.07)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
      )
      ..drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_NotchedBarPainter oldDelegate) => false;
}
