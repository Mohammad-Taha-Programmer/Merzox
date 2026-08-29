import 'package:flutter/material.dart';
import 'package:merzox/core/constants/colors.dart';

/// One onboarding artboard, laid out on the locked Merzox design canvas.
///
/// The Adobe XD artboard is 375x812 and reserves 44px of status chrome at the
/// top and 34px of home chrome at the bottom. Flutter never draws that chrome,
/// so the application design canvas is [designWidth] x [designHeight] and every
/// constant below is an XD *application-space* coordinate inside it.
///
/// The page therefore renders at its natural design size and expects to be
/// scaled uniformly by whatever hosts it; `OnboardingScreen` owns that scaling.
class OnboardingPage extends StatelessWidget {
  /// The XD artboard width, which carries no operating-system chrome.
  static const double designWidth = 375.0;

  /// The XD artboard height (812) minus its 44px status and 34px home chrome.
  static const double designHeight = 734.0;

  /// The illustration's locked visible box.
  ///
  /// The onboarding art has no transparent margin, so this rect matches the
  /// asset's own aspect ratio and `BoxFit.contain` fills it exactly - the image
  /// is placed, never cropped or stretched.
  static const Rect _illustrationRect = Rect.fromLTWH(
    46.0,
    105.0,
    283.0,
    218.0,
  );

  static const double _titleBaseline = 401.0;
  static const double _titleFontSize = 16.0;

  static const double _subtitleBaseline = 437.0;
  static const double _subtitleFontSize = 13.0;

  /// XD places the two Arabic subtitle baselines at y=437 and y=462.
  static const double _subtitleLineSpacing = 25.0;

  /// Horizontal inset of the bounded, centered subtitle column.
  ///
  /// It is the wrap width - not a manual line break - that gives the Arabic
  /// subtitle the two lines the reference shows.
  static const double _subtitleInset = 48.0;

  final String imagePath;
  final String title;
  final String subtitle;

  const OnboardingPage({
    super.key,
    required this.imagePath,
    required this.title,
    required this.subtitle,
  });

  /// Places [child] so its first text baseline lands [baseline] pixels below
  /// the top of the design canvas, which is how XD specifies the copy.
  static Widget _baselineText({
    required double baseline,
    required double left,
    required double width,
    required Widget child,
  }) {
    return Positioned(
      left: left,
      top: 0.0,
      child: Baseline(
        baseline: baseline,
        baselineType: TextBaseline.alphabetic,
        // `Baseline` loosens its constraints before laying the child out, so
        // the box the text centers within has to be stated on the child rather
        // than on the `Positioned`.
        child: SizedBox(width: width, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: designWidth,
      height: designHeight,
      child: Stack(
        children: <Widget>[
          Positioned.fromRect(
            rect: _illustrationRect,
            child: Image.asset(imagePath, fit: BoxFit.contain),
          ),
          _baselineText(
            baseline: _titleBaseline,
            left: 0.0,
            width: designWidth,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: _titleFontSize,
                fontWeight: FontWeight.bold,
                color: MerzoxColors.kColor2B2B2B,
              ),
            ),
          ),
          _baselineText(
            baseline: _subtitleBaseline,
            left: _subtitleInset,
            width: designWidth - 2 * _subtitleInset,
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: _subtitleFontSize,
                color: MerzoxColors.kColor2B2B2B,
                height: _subtitleLineSpacing / _subtitleFontSize,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
