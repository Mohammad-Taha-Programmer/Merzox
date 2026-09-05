import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:merzox/core/auth/auth_gate.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/core/constants/money.dart';
import 'package:merzox/features/cart/bloc/cart_bloc.dart';
import 'package:merzox/features/cart/bloc/cart_event.dart';
import 'package:merzox/features/cart/bloc/cart_state.dart';
import 'package:merzox/features/home/widgets/plain_tab_title.dart';

/// The basket tab.
///
/// It lived inside `home_screen` as a private widget, which put it out of
/// reach of every test: rendering it meant standing up the whole signed-in
/// home screen. That mattered - the tab was showing customers the raw text
/// `orders.checkoutOutOfStock` when an order was refused, and no test could
/// have caught it. Out here it is a widget a test can simply build.
class CartItemsView extends StatelessWidget {
  final VoidCallback onExplorePressed;

  const CartItemsView({required this.onExplorePressed, super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CartBloc, CartState>(
      listenWhen: (previous, current) =>
          previous.messageCode != current.messageCode ||
          previous.errorMessage != current.errorMessage,
      listener: (context, state) {
        final bool isCode = state.messageCode.isNotEmpty;
        final String code = isCode ? state.messageCode : state.errorMessage;
        if (code.isEmpty) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            // Both fields carry a translation key. The failure branch used to
            // go through `localizeApiErrorOrRaw`, which only translates keys
            // under `apiErrors.` and hands everything else back untouched -
            // so a customer whose order was refused read the literal text
            // `orders.checkoutOutOfStock`.
            content: Text(code.tr()),
            action: state.messageCode.isEmpty
                ? null
                : SnackBarAction(
                    label: 'orders.title'.tr(),
                    onPressed: () => context.push('/orders'),
                  ),
          ),
        );
      },
      builder: (context, state) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 118),
          children: [
            PlainTabTitle(title: 'nav.cart'.tr()),
            if (state.status == CartStatus.loading)
              const Padding(
                padding: EdgeInsets.only(top: 160),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (state.items.isEmpty)
              _EmptyCartState(onExplorePressed: onExplorePressed)
            else ...[
              const SizedBox(height: 20),
              ...state.items.map(
                (item) => _CartItemTile(
                  item: item,
                  onRemove: () {
                    context.read<CartBloc>().add(CartItemRemoved(item.raw));
                  },
                ),
              ),
              const SizedBox(height: 18),
              _CartSummaryCard(
                subtotal: state.subtotal,
                // The basket no longer submits itself: the customer confirms
                // the address and the invoice first, and that screen dispatches
                // the same event this button used to.
                onCheckoutPressed: state.status == CartStatus.checkingOut
                    ? null
                    : () => AuthGate.run(
                        context,
                        onAuthenticated: () => context.push('/checkout'),
                      ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _EmptyCartState extends StatelessWidget {
  final VoidCallback onExplorePressed;

  const _EmptyCartState({required this.onExplorePressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height - 210,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CustomPaint(
            size: const Size(122, 156),
            painter: _EmptyCartBagPainter(),
          ),
          const SizedBox(height: 28),
          Text(
            'home.cart.emptyTitle'.tr(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2B2B2B),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'home.cart.emptyBody'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.65,
              color: MerzoxColors.kColor707070,
            ),
          ),
          const SizedBox(height: 58),
          SizedBox(
            width: 204,
            height: 48,
            child: FilledButton(
              onPressed: onExplorePressed,
              style: FilledButton.styleFrom(
                backgroundColor: MerzoxColors.kColorEE6C4D,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              child: Text(
                'home.cart.exploreShopping'.tr(),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartItemTile extends StatelessWidget {
  final CartItem item;
  final VoidCallback onRemove;

  const _CartItemTile({required this.item, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        _card(context),
        // `السلة – 1` drops a line from a small ✕ at the corner of its card,
        // which is what the stepper freed the row of: a minus that empties a
        // line by accident is not a remove button.
        PositionedDirectional(
          top: 2,
          end: 2,
          child: InkWell(
            onTap: onRemove,
            customBorder: const CircleBorder(),
            child: Tooltip(
              message: 'common.remove'.tr(),
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: MerzoxColors.kColor98C1D9,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _card(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MerzoxColors.kColorEFEFEF),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        textDirection: Directionality.of(context),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 72,
              height: 72,
              child: item.imageUrl.isEmpty
                  ? const _CartImageFallback()
                  : Image.network(
                      item.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const _CartImageFallback(),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (item.variantLabel.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    item.variantLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: Directionality.of(context),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: MerzoxColors.kColor8D99AE,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  'home.cart.quantity'.tr(args: ['${item.quantity}']),
                  textDirection: Directionality.of(context),
                  style: TextStyle(
                    fontSize: 12,
                    color: MerzoxColors.kColor767676,
                  ),
                ),
                // Shown only when the public contract said so on the last
                // refresh; checkout refuses while any line reads like this.
                if (!item.inStock)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'catalog.outOfStock'.tr(),
                      textDirection: Directionality.of(context),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: MerzoxColors.kColorEE6C4D,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  textDirection: Directionality.of(context),
                  children: [
                    Text(
                      '\u20AA ${merzoxAmount(item.total)}',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: MerzoxColors.kColor3D5A80,
                      ),
                    ),
                    const Spacer(),
                    _QuantityStepper(
                      quantity: item.quantity,
                      onChanged: (int next) => context.read<CartBloc>().add(
                        CartItemQuantityChanged(raw: item.raw, quantity: next),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CartSummaryCard extends StatelessWidget {
  final double subtotal;
  final VoidCallback? onCheckoutPressed;

  const _CartSummaryCard({
    required this.subtotal,
    required this.onCheckoutPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MerzoxColors.kColorEFEFEF),
      ),
      child: Column(
        children: [
          _SummaryRow(
            label: 'home.cart.subtotal'.tr(),
            value: '\u20AA ${merzoxAmount(subtotal)}',
          ),
          const SizedBox(height: 8),
          _SummaryRow(
            label: 'orders.delivery'.tr(),
            value: 'home.cart.deliveryCalculatedLater'.tr(),
          ),
          const Divider(height: 24),
          _SummaryRow(
            label: 'home.cart.total'.tr(),
            value: '\u20AA ${merzoxAmount(subtotal)}',
            isStrong: true,
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: onCheckoutPressed,
            style: FilledButton.styleFrom(
              backgroundColor: MerzoxColors.kColorEE6C4D,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text('home.cart.checkout'.tr()),
          ),
        ],
      ),
    );
  }
}

class _EmptyCartBagPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = MerzoxColors.kColor3D5A80
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.08,
        size.height * 0.25,
        size.width * 0.84,
        size.height * 0.65,
      ),
      const Radius.circular(5),
    );
    canvas.drawRRect(body, paint);
    canvas.drawLine(
      Offset(size.width * 0.08, size.height * 0.32),
      Offset(size.width * 0.92, size.height * 0.32),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.08, size.height * 0.82),
      Offset(size.width * 0.92, size.height * 0.82),
      paint,
    );

    final handle = Path()
      ..moveTo(size.width * 0.38, size.height * 0.25)
      ..lineTo(size.width * 0.38, size.height * 0.16)
      ..quadraticBezierTo(
        size.width * 0.38,
        size.height * 0.08,
        size.width * 0.5,
        size.height * 0.08,
      )
      ..quadraticBezierTo(
        size.width * 0.62,
        size.height * 0.08,
        size.width * 0.62,
        size.height * 0.16,
      )
      ..lineTo(size.width * 0.62, size.height * 0.25);
    canvas.drawPath(handle, paint);

    final fillPaint = Paint()
      ..color = MerzoxColors.kColor3D5A80
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(size.width * 0.43, size.height * 0.56),
      3.5,
      fillPaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.57, size.height * 0.56),
      3.5,
      fillPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.42, size.height * 0.67),
      Offset(size.width * 0.58, size.height * 0.67),
      paint..strokeWidth = 2.2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _QuantityStepper extends StatelessWidget {
  final int quantity;
  final ValueChanged<int> onChanged;

  const _QuantityStepper({required this.quantity, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: MerzoxColors.kColor3D5A80,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        textDirection: TextDirection.ltr,
        children: <Widget>[
          _StepperButton(
            icon: Icons.remove_rounded,
            // One is the floor: dropping a line is the ✕'s job, not a
            // decrement that empties it by accident.
            onPressed: quantity > 1 ? () => onChanged(quantity - 1) : null,
          ),
          Container(
            width: 30,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$quantity',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: MerzoxColors.kColor2B2B2B,
              ),
            ),
          ),
          _StepperButton(
            icon: Icons.add_rounded,
            onPressed: quantity < CartBloc.maxLineQuantity
                ? () => onChanged(quantity + 1)
                : null,
          ),
        ],
      ),
    );
  }
}

class _CartImageFallback extends StatelessWidget {
  const _CartImageFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MerzoxColors.kColorEEF6FB,
      child: Icon(
        Icons.shopping_bag_outlined,
        color: MerzoxColors.kColor3D5A80,
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isStrong;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.isStrong = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isStrong ? 15 : 13,
            fontWeight: isStrong ? FontWeight.w800 : FontWeight.w500,
            color: const Color(0xFF2B2B2B),
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: isStrong ? 15 : 13,
            fontWeight: isStrong ? FontWeight.w800 : FontWeight.w600,
            color: isStrong
                ? MerzoxColors.kColorEE6C4D
                : MerzoxColors.kColor767676,
          ),
        ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _StepperButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 28,
        height: 28,
        child: Icon(
          icon,
          size: 16,
          color: onPressed == null ? MerzoxColors.kColor8D99AE : Colors.white,
        ),
      ),
    );
  }
}
