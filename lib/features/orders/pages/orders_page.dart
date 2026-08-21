import 'dart:math' as math;
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/features/home/widgets/feature_bottom_navigation_bar.dart';
import 'package:merzox/features/orders/bloc/orders_bloc.dart';
import 'package:merzox/features/orders/bloc/orders_event.dart';
import 'package:merzox/features/orders/bloc/orders_state.dart';

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
            : state.errorMessage;
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
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [SizedBox(height: 92), _EmptyOrdersState()],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        context.read<OrdersBloc>().add(const OrdersRefreshRequested());
      },
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
        itemCount:
            state.orders.length +
            (state.status == OrdersStatus.loadingMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 14),
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
    return SizedBox(
      width: double.infinity,
      height: 82,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            'orders.title'.tr(),
            style: const TextStyle(
              color: MerzoxColors.kColor2B2B2B,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          PositionedDirectional(
            start: 8,
            child: const BackButton(color: MerzoxColors.kColor5E5E5E),
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
      height: 46,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: MerzoxColors.kColor98C1D9),
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
                color: selected ? Colors.white : MerzoxColors.kColor3B3B3B,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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
    return Container(width: 1, color: MerzoxColors.kColor98C1D9);
  }
}

class _OrderListItem extends StatelessWidget {
  final OrderApiModel order;
  final OrdersGroup group;
  final bool cancelling;
  final VoidCallback onCancel;

  const _OrderListItem({
    required this.order,
    required this.group,
    required this.cancelling,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final card = _OrderCard(order: order, group: group);
    if (group != OrdersGroup.current) return card;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 330) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              card,
              const SizedBox(height: 8),
              SizedBox(
                height: 42,
                child: _CancelOrderButton(
                  cancelling: cancelling,
                  onPressed: onCancel,
                ),
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: card),
            const SizedBox(width: 10),
            SizedBox(
              width: 92,
              height: 50,
              child: _CancelOrderButton(
                cancelling: cancelling,
                onPressed: onCancel,
              ),
            ),
          ],
        );
      },
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
    final date = _formatDate(order.createdAt);

    return Container(
      constraints: const BoxConstraints(minHeight: 142),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: MerzoxColors.kColorF5F9FC,
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
                    fontSize: 10,
                    color: Color(0xFF3B3B3B),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${'orders.orderDate'.tr()}: $date',
                style: const TextStyle(fontSize: 10, color: Color(0xFF3B3B3B)),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _OrderProductImage(imageUrl: firstItem?.imageUrl ?? ''),
              const SizedBox(width: 10),
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
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _OrderMetric(
                          label: 'orders.price'.tr(),
                          value: _money(order.subtotal),
                        ),
                        _OrderMetric(
                          label: 'orders.delivery'.tr(),
                          value: _money(order.deliveryFee),
                        ),
                        _OrderMetric(
                          label: 'orders.quantity'.tr(),
                          value:
                              '${order.items.fold<int>(0, (sum, item) => sum + item.quantity)}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Container(
                        height: 28,
                        constraints: const BoxConstraints(minWidth: 84),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: MerzoxColors.kColorEE6C4D,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          '${'orders.total'.tr()} ${_money(order.total)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 34,
            child: OutlinedButton.icon(
              onPressed: () => context.push('/orders/${order.id}/tracking'),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                side: const BorderSide(color: MerzoxColors.kColor3D5A80),
                foregroundColor: MerzoxColors.kColor3D5A80,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              icon: const Icon(Icons.local_shipping_outlined, size: 15),
              label: Text(
                'tracking.trackOrder'.tr(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (group == OrdersGroup.cancelled &&
              order.cancellationReason.isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(
              '${'orders.cancelledReason'.tr()}: ${order.cancellationReason}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                height: 1.35,
                color: MerzoxColors.kColor5E5E5E,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OrderMetric extends StatelessWidget {
  final String label;
  final String value;

  const _OrderMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 9, color: MerzoxColors.kColor707070),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          textDirection: TextDirection.ltr,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: MerzoxColors.kColor2B2B2B,
          ),
        ),
      ],
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
      child: SizedBox(width: 66, height: 76, child: image),
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
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
    );
  }
}

class _EmptyOrdersState extends StatelessWidget {
  const _EmptyOrdersState();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CustomPaint(
          size: const Size(132, 170),
          painter: _OrdersChecklistPainter(),
        ),
        const SizedBox(height: 56),
        Text(
          'orders.empty'.tr(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: MerzoxColors.kColor2B2B2B,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 34),
          child: Text(
            'orders.emptyHint'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MerzoxColors.kColor707070,
              fontSize: 12,
              height: 1.5,
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

class _OrdersChecklistPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = MerzoxColors.kColor3D5A80
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final page = RRect.fromRectAndRadius(
      Rect.fromLTWH(5, 4, size.width - 10, size.height - 8),
      const Radius.circular(2),
    );
    canvas.drawRRect(page, paint);

    for (var index = 0; index < 3; index++) {
      final y = 45.0 + index * 43;
      final check = Path()
        ..moveTo(25, y)
        ..lineTo(37, y + 12)
        ..lineTo(56, y - 9);
      canvas.drawPath(check, paint);
      canvas.drawLine(Offset(75, y + 2), Offset(size.width - 22, y + 2), paint);
    }

    final shortY = math.min(size.height - 31, 151.0);
    canvas.drawLine(Offset(75, shortY), Offset(size.width - 22, shortY), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

String _formatDate(DateTime? value) {
  if (value == null) return '--/--/----';
  final local = value.toLocal();
  return '${local.day}/${local.month}/${local.year}';
}

String _money(double value) {
  final formatted = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
  return '$formatted ${'common.currency'.tr()}';
}
