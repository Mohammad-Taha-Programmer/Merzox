import 'package:flutter/material.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/core/widgets/merzox_icons.dart';

/// The three checkout steps, in the order the artboards draw them.
///
/// Right to left in Arabic: buyer details, then payment, then the confirmed
/// order. The enum's own order is that reading order, so `index` is the step
/// number and nothing has to reverse it.
enum CheckoutStep { buyerDetails, payment, confirmed }

/// The strip of three step chips above every checkout screen.
///
/// Sizes are measured from `تفاصيل المتجر – 16` and `– 24`: 48x48 chips with a
/// 4px radius, 24px apart, joined by a dotted rule. The active chip is filled
/// navy with a white glyph; the others are outlined with a grey one.
class CheckoutStepIndicator extends StatelessWidget {
  final CheckoutStep current;

  const CheckoutStepIndicator({super.key, required this.current});

  static const double _chipSize = 48;
  static const double _chipRadius = 4;
  static const double _gap = 24;

  /// What each chip draws, and how large.
  ///
  /// The size travels with the glyph because each mark fills its em box its
  /// own way, and drawing all three at 22 would put them at three different
  /// apparent sizes.
  ///
  /// All three are this library's now. The tick used to be Material's, because
  /// the designer's set has no tick of any kind - and it showed: a heavier
  /// stroke than the two beside it, a guest on its own strip. The one here was
  /// drawn to the family's measured weight to stand with them, and is the only
  /// mark in the set nobody designed. When a real one arrives it is one file
  /// to replace and nothing else moves.
  static const List<({IconData icon, double size})> _steps =
      <({IconData icon, double size})>[
        (
          icon: MerzoxIcons.checkoutStepsOrderData,
          size: _glyphSize * MerzoxIcons.orderDataSizeFactor,
        ),
        (
          icon: MerzoxIcons.checkoutStepsOrderPayment,
          size: _glyphSize * MerzoxIcons.orderPaymentSizeFactor,
        ),
        (
          icon: MerzoxIcons.checkoutStepsOrderDone,
          size: _glyphSize * MerzoxIcons.orderDoneSizeFactor,
        ),
      ];

  static const double _glyphSize = 22;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _chipSize,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          for (int step = 0; step < _steps.length; step++) ...<Widget>[
            if (step > 0) const _StepConnector(width: _gap),
            _StepChip(
              icon: _steps[step].icon,
              iconSize: _steps[step].size,
              active: step == current.index,
            ),
          ],
        ],
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  final IconData icon;
  final double iconSize;
  final bool active;

  const _StepChip({
    required this.icon,
    required this.iconSize,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: CheckoutStepIndicator._chipSize,
      height: CheckoutStepIndicator._chipSize,
      decoration: BoxDecoration(
        color: active ? MerzoxColors.kColor3D5A80 : Colors.white,
        borderRadius: BorderRadius.circular(CheckoutStepIndicator._chipRadius),
        border: Border.all(
          color: active ? MerzoxColors.kColor3D5A80 : MerzoxColors.kColorD8D8D8,
        ),
      ),
      child: Icon(
        icon,
        size: iconSize,
        color: active ? Colors.white : MerzoxColors.kColorBEBEBE,
      ),
    );
  }
}

/// The dotted rule between two chips.
class _StepConnector extends StatelessWidget {
  final double width;

  const _StepConnector({required this.width});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 1,
      child: CustomPaint(painter: _DottedRulePainter()),
    );
  }
}

class _DottedRulePainter extends CustomPainter {
  static const double _dash = 3;
  static const double _space = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = MerzoxColors.kColorD8D8D8
      ..strokeWidth = 1;

    for (double x = 0; x < size.width; x += _dash + _space) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset((x + _dash).clamp(0, size.width), size.height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DottedRulePainter oldDelegate) => false;
}
