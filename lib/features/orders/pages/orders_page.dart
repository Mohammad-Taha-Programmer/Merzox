import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:merzox/core/constants/dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/features/home/widgets/feature_bottom_navigation_bar.dart';
import 'package:merzox/features/orders/bloc/orders_bloc.dart';
import 'package:merzox/features/orders/bloc/orders_event.dart';
import 'package:merzox/features/orders/bloc/orders_state.dart';
import 'package:merzox/core/localization/api_error_localizer.dart';
import 'package:merzox/core/constants/money.dart';

/// The band between the status bar and the tab strip, which every artboard in
/// the family draws the same.
const double _ordersHeaderHeight = 69;

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final remaining = _scrollController.position.extentAfter;
    if (remaining < 240) {
      context.read<OrdersBloc>().add(const OrdersLoadMoreRequested());
    }
  }

  Future<void> _confirmCancellation(OrderApiModel order) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('orders.cancelTitle'.tr()),
        content: TextField(
          controller: controller,
          maxLength: 250,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'orders.cancelReason'.tr(),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: MerzoxColors.kColorEE6C4D,
            ),
            child: Text('common.confirm'.tr()),
          ),
        ],
      ),
    );
    final reason = controller.text.trim();
    controller.dispose();

    if (confirmed == true && mounted) {
      context.read<OrdersBloc>().add(
        OrderCancellationRequested(orderId: order.id, reason: reason),
      );
    }
  }

  void _openHomeTab(int index) {
    context.go('/home?tab=$index');
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<OrdersBloc, OrdersState>(
      listenWhen: (previous, current) {
        return (current.messageCode.isNotEmpty &&
                previous.messageCode != current.messageCode) ||
            (current.errorMessage.isNotEmpty &&
                previous.errorMessage != current.errorMessage);
      },
      listener: (context, state) {
        final message = state.messageCode.isNotEmpty
            ? state.messageCode.tr()
            : localizeApiErrorOrRaw(state.errorMessage);
        if (message.isNotEmpty) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
      },
      builder: (context, state) {
        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                const _OrdersHeader(),
                if (state.totalOrderCount > 0)
                  _OrdersTabs(selectedGroup: state.selectedGroup),
                Expanded(child: _buildContent(state)),
              ],
            ),
          ),
          bottomNavigationBar: FeatureBottomNavigationBar(
            selectedIndex: 4,
            onChanged: _openHomeTab,
          ),
        );
      },
    );
  }

  Widget _buildContent(OrdersState state) {
    if (state.status == OrdersStatus.loading) {
      return const Center(
        child: CircularProgressIndicator(color: MerzoxColors.kColor3D5A80),
      );
    }

    if (state.status == OrdersStatus.failure && state.orders.isEmpty) {
      return _OrdersFailureState(
        onRetry: () {
          context.read<OrdersBloc>().add(const OrdersRefreshRequested());
        },
      );
    }

    if (state.orders.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async {
          context.read<OrdersBloc>().add(const OrdersRefreshRequested());
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            return ListView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                // `السلة – 4` starts the block 110px under the header rather
                // than centring it in what is left of the screen: where the
                // bottom bar ends is not what the artboard measures from.
                ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: const Padding(
                    padding: EdgeInsets.only(top: 110),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: _EmptyOrdersState(),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        context.read<OrdersBloc>().add(const OrdersRefreshRequested());
      },
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 25, 16, 28),
        itemCount:
            state.orders.length +
            (state.status == OrdersStatus.loadingMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          if (index == state.orders.length) {
            return const Padding(
              padding: EdgeInsets.all(14),
              child: Center(
                child: CircularProgressIndicator(
                  color: MerzoxColors.kColor3D5A80,
                ),
              ),
            );
          }

          final order = state.orders[index];
          return _OrderListItem(
            key: ValueKey<String>(order.id),
            order: order,
            group: state.selectedGroup,
            cancelling: state.cancellingOrderId == order.id,
            onCancel: () => _confirmCancellation(order),
          );
        },
      ),
    );
  }
}

class _OrdersHeader extends StatelessWidget {
  const _OrdersHeader();

  @override
  Widget build(BuildContext context) {
    // The artboards put the title's baseline 31px below the status bar and the
    // tab strip 69px below it, so the title is not centred in the band it
    // occupies and a `Stack.center` would sit it 8px too low.
    return SizedBox(
      width: double.infinity,
      height: _ordersHeaderHeight,
      child: Stack(
        children: [
          const PositionedDirectional(
            start: 5,
            top: 1,
            child: BackButton(color: MerzoxColors.kColor5E5E5E),
          ),
          Positioned(
            top: 14,
            left: 0,
            right: 0,
            child: Text(
              'orders.title'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MerzoxColors.kColor2B2B2B,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrdersTabs extends StatelessWidget {
  final OrdersGroup selectedGroup;

  const _OrdersTabs({required this.selectedGroup});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: MerzoxColors.kColor3D5A80),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        children: [
          _OrderTab(
            group: OrdersGroup.current,
            label: 'orders.current'.tr(),
            selected: selectedGroup == OrdersGroup.current,
          ),
          const _TabDivider(),
          _OrderTab(
            group: OrdersGroup.completed,
            label: 'orders.completed'.tr(),
            selected: selectedGroup == OrdersGroup.completed,
          ),
          const _TabDivider(),
          _OrderTab(
            group: OrdersGroup.cancelled,
            label: 'orders.cancelled'.tr(),
            selected: selectedGroup == OrdersGroup.cancelled,
          ),
        ],
      ),
    );
  }
}

class _OrderTab extends StatelessWidget {
  final OrdersGroup group;
  final String label;
  final bool selected;

  const _OrderTab({
    required this.group,
    required this.label,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: selected ? MerzoxColors.kColor3D5A80 : Colors.white,
        child: InkWell(
          onTap: () =>
              context.read<OrdersBloc>().add(OrdersGroupChanged(group)),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : MerzoxColors.kColor2B2B2B,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabDivider extends StatelessWidget {
  const _TabDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, color: MerzoxColors.kColor3D5A80);
  }
}

/// A current order's card over the cancel action the artboards hide behind it.
///
/// `تفاصيل المتجر – 22` and `– 37` both draw the first card slid aside with an
/// orange `الغاء الطلب` running off the far edge, which is a swipe being shown
/// mid-gesture — not a button that permanently narrows every card. The old
/// layout reserved 92px beside the card for it and cost the card a quarter of
/// its width on the one tab that has the most to say.
class _OrderListItem extends StatefulWidget {
  final OrderApiModel order;
  final OrdersGroup group;
  final bool cancelling;
  final VoidCallback onCancel;

  const _OrderListItem({
    super.key,
    required this.order,
    required this.group,
    required this.cancelling,
    required this.onCancel,
  });

  @override
  State<_OrderListItem> createState() => _OrderListItemState();
}

class _OrderListItemState extends State<_OrderListItem> {
  /// How far the card slides, which is how wide the action underneath is.
  static const double _revealWidth = 120;

  double _offset = 0;

  bool get _open => _offset > _revealWidth / 2;

  void _drag(DragUpdateDetails details, TextDirection direction) {
    // The action lives at the logical end, so the card travels towards the
    // logical start: rightwards in Arabic, leftwards in English.
    final double delta = direction == TextDirection.rtl
        ? details.delta.dx
        : -details.delta.dx;
    setState(() => _offset = (_offset + delta).clamp(0.0, _revealWidth));
  }

  void _settle() => setState(() => _offset = _open ? _revealWidth : 0);

  @override
  Widget build(BuildContext context) {
    final card = _OrderCard(order: widget.order, group: widget.group);
    if (widget.group != OrdersGroup.current) return card;

    final TextDirection direction = Directionality.of(context);
    final double signed = direction == TextDirection.rtl ? _offset : -_offset;

    return GestureDetector(
      onHorizontalDragUpdate: (details) => _drag(details, direction),
      onHorizontalDragEnd: (_) => _settle(),
      onHorizontalDragCancel: _settle,
      child: Stack(
        children: [
          PositionedDirectional(
            top: 0,
            bottom: 0,
            end: 0,
            width: _revealWidth,
            child: Center(
              child: SizedBox(
                width: _revealWidth - 12,
                height: 48,
                child: _CancelOrderButton(
                  cancelling: widget.cancelling,
                  onPressed: () {
                    setState(() => _offset = 0);
                    widget.onCancel();
                  },
                ),
              ),
            ),
          ),
          Transform.translate(offset: Offset(signed, 0), child: card),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final OrderApiModel order;
  final OrdersGroup group;

  const _OrderCard({required this.order, required this.group});

  @override
  Widget build(BuildContext context) {
    final firstItem = order.items.isEmpty ? null : order.items.first;
    final date = merzoxDay(order.createdAt);
    final bool current = group == OrdersGroup.current;

    return Container(
      padding: const EdgeInsets.fromLTRB(13, 13, 13, 15),
      decoration: BoxDecoration(
        color: MerzoxColors.kColorF3F7FA,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${'orders.orderNumber'.tr()}: ${order.publicId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: MerzoxColors.kColor3B3B3B,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${'orders.orderDate'.tr()}: $date',
                style: const TextStyle(
                  fontSize: 11,
                  color: MerzoxColors.kColor3B3B3B,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _OrderProductImage(imageUrl: firstItem?.imageUrl ?? ''),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      firstItem?.name ?? order.business.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MerzoxColors.kColor2B2B2B,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if ((firstItem?.variant ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        firstItem!.variant,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: MerzoxColors.kColor8D99AE,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (order.items.length > 1) ...[
                      const SizedBox(height: 2),
                      Text(
                        'orders.moreItems'.tr(
                          args: ['${order.items.length - 1}'],
                        ),
                        style: const TextStyle(
                          color: MerzoxColors.kColor707070,
                          fontSize: 10,
                        ),
                      ),
                    ],
                    const SizedBox(height: 3),
                    // Price, quantity, delivery - in that reading order, and
                    // with the number beside its label rather than under it.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _OrderMetric(
                          label: 'orders.price'.tr(),
                          value: merzoxAmount(order.subtotal),
                        ),
                        _OrderMetric(
                          label: 'orders.quantity'.tr(),
                          value:
                              '${order.items.fold<int>(0, (sum, item) => sum + item.quantity)}',
                        ),
                        _OrderMetric(
                          label: 'orders.delivery'.tr(),
                          value: merzoxAmount(order.deliveryFee),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _OrderChip(
                          // The artboard labels this chip `السعر` even though
                          // it carries the total, one line under a `السعر`
                          // that carries the subtotal. Two different numbers
                          // cannot share a name, so the total says so.
                          label: 'orders.total'.tr(),
                          value: _money(order.total),
                          color: current
                              ? MerzoxColors.kColor3D5A80
                              : MerzoxColors.kColorEE6C4D,
                        ),
                        if (current) ...[
                          const SizedBox(width: 10),
                          _OrderChip(
                            label: 'tracking.trackOrder'.tr(),
                            color: MerzoxColors.kColorEE6C4D,
                            onTap: () =>
                                context.push('/orders/${order.id}/tracking'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (group == OrdersGroup.cancelled &&
              order.cancellationReason.isNotEmpty) ...[
            const SizedBox(height: 8),
            // The artboard sets this at 14, on a seventeen-character sample.
            // A cancellation reason is free text up to 250 characters, and at
            // 14 a realistic one wraps the card past the height drawn.
            Text(
              '${'orders.cancelledReason'.tr()}: ${order.cancellationReason}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                color: MerzoxColors.kColor3B3B3B,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A label and its number on one line, the way the artboards set them.
class _OrderMetric extends StatelessWidget {
  final String label;
  final String value;

  const _OrderMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: MerzoxColors.kColor3B3B3B,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          textDirection: TextDirection.ltr,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: MerzoxColors.kColor3B3B3B,
          ),
        ),
      ],
    );
  }
}

/// One of the card's two pills: 99x30, white on a solid fill.
class _OrderChip extends StatelessWidget {
  final String label;
  final String? value;
  final Color color;
  final VoidCallback? onTap;

  const _OrderChip({
    required this.label,
    required this.color,
    this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 99x30 is the size the artboards draw, and it fits `المجموع 45 ₪` in
    // Tajawal. A fallback face is wider, so the label scales rather than
    // striping the chip with an overflow.
    final Widget content = Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: value == null ? 12 : 10,
                fontWeight: value == null ? FontWeight.w700 : FontWeight.w500,
                color: Colors.white,
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: 6),
              Text(
                value!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return SizedBox(
      width: 99,
      height: 30,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(5),
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

class _OrderProductImage extends StatelessWidget {
  final String imageUrl;

  const _OrderProductImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: Colors.white,
      alignment: Alignment.center,
      child: const Icon(
        Icons.inventory_2_outlined,
        color: MerzoxColors.kColor98C1D9,
        size: 28,
      ),
    );

    Widget image = placeholder;
    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      image = Image.network(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      );
    } else if (imageUrl.startsWith('assets/')) {
      image = Image.asset(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(width: 84, height: 84, child: image),
    );
  }
}

class _CancelOrderButton extends StatelessWidget {
  final bool cancelling;
  final VoidCallback onPressed;

  const _CancelOrderButton({required this.cancelling, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: cancelling ? null : onPressed,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        backgroundColor: MerzoxColors.kColorEE6C4D,
        foregroundColor: Colors.white,
        disabledBackgroundColor: MerzoxColors.kColorFEE3DC,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      child: cancelling
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: MerzoxColors.kColorEE6C4D,
              ),
            )
          : Text(
              'orders.cancelOrder'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
    );
  }
}

class _EmptyOrdersState extends StatelessWidget {
  const _EmptyOrdersState();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size(150, 200),
          painter: _OrdersChecklistPainter(),
        ),
        const SizedBox(height: 81),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'orders.empty'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MerzoxColors.kColor2B2B2B,
              fontSize: 16,
            ),
          ),
        ),
      ],
    );
  }
}

class _OrdersFailureState extends StatelessWidget {
  final VoidCallback onRetry;

  const _OrdersFailureState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.receipt_long_outlined,
              size: 76,
              color: MerzoxColors.kColor3D5A80,
            ),
            const SizedBox(height: 24),
            Text(
              'orders.loadError'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: onRetry,
              child: Text('common.retry'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

/// The checklist `السلة – 4` draws: a 150x200 page, three ticked rows and a
/// fourth rule with no tick, all in one 11px stroke.
class _OrdersChecklistPainter extends CustomPainter {
  static const double _stroke = 11;
  static const double _rowPitch = 36;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = MerzoxColors.kColor3D5A80
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final half = _stroke / 2;
    final page = RRect.fromRectAndRadius(
      Rect.fromLTWH(half, half, size.width - _stroke, size.height - _stroke),
      const Radius.circular(3),
    );
    canvas.drawRRect(page, paint);

    final ruleEnd = size.width - 28;
    for (var index = 0; index < 4; index++) {
      final y = 50.0 + index * _rowPitch;
      // The fourth row is a rule with no tick against it.
      if (index < 3) {
        final tick = Path()
          ..moveTo(32, y)
          ..lineTo(40, y + 10)
          ..lineTo(60, y - 12);
        canvas.drawPath(tick, paint);
      }
      canvas.drawLine(Offset(75, y), Offset(ruleEnd, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

String _money(double value) {
  return '${merzoxAmount(value)} ${'common.currency'.tr()}';
}
