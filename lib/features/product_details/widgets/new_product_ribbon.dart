import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';

import '../../../core/constants/colors.dart';

/// The `جديد` flag the artboard hangs on a product's photo.
///
/// It belongs to the product, not to the picture being shown, so it is drawn
/// over the slider rather than inside it - paging to the second photo must not
/// take the flag with it.
///
/// The shape is `Path 37123` from `تفاصيل المتجر – 38`, resolved out of the
/// quarter-turn its group carries: a 29.4 by 69.56 tab rising from the foot of
/// the picture, with a notch cut down into its free end.
class NewProductRibbon extends StatelessWidget {
  const NewProductRibbon({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kNewRibbonWidth,
      height: kNewRibbonHeight,
      child: CustomPaint(
        painter: const NewProductRibbonPainter(),
        child: Padding(
          // Clear of the notch, so the word sits on the solid part of the tab.
          padding: const EdgeInsets.only(top: kNewRibbonNotchDepth),
          child: Center(
            // Read bottom to top, the way a tab down the edge of a page is
            // read.
            child: RotatedBox(
              quarterTurns: 3,
              child: Text(
                'productDetails.newBadge'.tr(),
                maxLines: 1,
                style: const TextStyle(
                  fontSize: kNewRibbonTextSize,
                  fontWeight: FontWeight.w500,
                  color: MerzoxColors.kColor2B2B2B,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The artboard's own measurements for the tab.
const double kNewRibbonWidth = 29.4;
const double kNewRibbonHeight = 69.56;

/// How far the notch cuts into the free end.
const double kNewRibbonNotchDepth = 19.35;

/// Where the notch's point sits across the tab. Very nearly the middle, and
/// left as the board drew it rather than rounded to it.
const double kNewRibbonNotchCentre = 13.95;

const double kNewRibbonTextSize = 13;

/// How far the tab stands from the picture's near edge and its foot.
const double kNewRibbonInset = 59.8;

class NewProductRibbonPainter extends CustomPainter {
  const NewProductRibbonPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final double scaleX = size.width / kNewRibbonWidth;
    final double scaleY = size.height / kNewRibbonHeight;

    final Path tab = Path()
      // Up the near edge, across the notch, and down the far one.
      ..moveTo(0, size.height)
      ..lineTo(0, 0)
      ..lineTo(kNewRibbonNotchCentre * scaleX, kNewRibbonNotchDepth * scaleY)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..close();

    canvas.drawPath(tab, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(NewProductRibbonPainter oldDelegate) => false;
}
