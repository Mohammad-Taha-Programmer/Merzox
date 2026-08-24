import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/features/orders/order_status_policy.dart';

class MerchantOrderDetailPage extends StatelessWidget {
  final OwnerOrder order;
  final String businessName;
  final String businessAddress;
  final bool isSaving;

  /// Applying a status is owned by the shell's bloc, so the page reports the
  /// choice upward instead of talking to the API itself.
  final void Function(String status) onStatusSelected;
  final Future<void> Function(String name, String phone)? onCourierAssigned;

  const MerchantOrderDetailPage({
    super.key,
    required this.order,
    required this.businessName,
    required this.businessAddress,
    required this.onStatusSelected,
    this.onCourierAssigned,
    this.isSaving = false,
  });

  List<String> get _allowedStatuses =>
      OrderStatusPolicy.merchantTransitionsFrom(order.status);

  Future<void> _assignCourier(BuildContext context) async {
    final nameController = TextEditingController(text: order.courier.name);
    final phoneController = TextEditingController(text: order.courier.phone);

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('merchantOrder.assignCourier'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'merchantOrder.courierName'.tr(),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'merchantOrder.courierPhone'.tr(),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('common.save'.tr()),
          ),
        ],
      ),
    );

    final name = nameController.text.trim();
    final phone = phoneController.text.trim();
    nameController.dispose();
    phoneController.dispose();

    if (saved != true || name.isEmpty) return;
    await onCourierAssigned?.call(name, phone);
  }

  void _showInvoice(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _InvoiceSheet(
        order: order,
        businessName: businessName,
        businessAddress: businessAddress,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              height: 66,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    'merchantOrder.title'.tr(),
                    style: const TextStyle(
                      color: MerzoxColors.kColor2B2B2B,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const PositionedDirectional(
                    start: 8,
                    child: BackButton(color: MerzoxColors.kColor5E5E5E),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
                children: [
                  _StatusCard(
                    order: order,
                    allowedStatuses: _allowedStatuses,
                    isSaving: isSaving,
                    onStatusSelected: onStatusSelected,
                  ),
                  const SizedBox(height: 18),
                  _SectionTitle(
                    'merchantOrder.products'.tr(
                      args: ['${order.items.length}'],
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final item in order.items) _ItemRow(item: item),
                  const SizedBox(height: 18),
                  _SectionTitle('merchantOrder.customerAndDelivery'.tr()),
                  const SizedBox(height: 10),
                  _DetailCard(
                    lines: [
                      (
                        Icons.person_outline_rounded,
                        order.customerName.isEmpty ? '—' : order.customerName,
                      ),
                      (
                        Icons.location_on_outlined,
                        order.deliveryAddress.isEmpty
                            ? '—'
                            : order.deliveryAddress,
                      ),
                      (
                        Icons.phone_outlined,
                        order.customerPhone.isEmpty ? '—' : order.customerPhone,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _SectionTitle('merchantOrder.paymentMethod'.tr()),
                  const SizedBox(height: 8),
                  Text(
                    'merchantOrder.payment.${order.paymentMethod}'.tr(),
                    style: const TextStyle(
                      fontSize: 13,
                      color: MerzoxColors.kColor5E5E5E,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _CourierSection(
                    order: order,
                    onAssign: onCourierAssigned == null
                        ? null
                        : () => _assignCourier(context),
                  ),
                  const SizedBox(height: 18),
                  _SectionTitle('merchantOrder.invoice'.tr()),
                  const SizedBox(height: 10),
                  _InvoiceSummary(order: order),
                  const SizedBox(height: 22),
                  OutlinedButton.icon(
                    onPressed: () => _showInvoice(context),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      side: const BorderSide(color: MerzoxColors.kColor3D5A80),
                      foregroundColor: MerzoxColors.kColor3D5A80,
                    ),
                    icon: const Icon(Icons.receipt_long_rounded, size: 18),
                    label: Text('merchantOrder.viewInvoice'.tr()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final OwnerOrder order;
  final List<String> allowedStatuses;
  final bool isSaving;
  final void Function(String status) onStatusSelected;

  const _StatusCard({
    required this.order,
    required this.allowedStatuses,
    required this.isSaving,
    required this.onStatusSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MerzoxColors.kColorF9F9F9,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MerzoxColors.kColorEFEFEF),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'merchantOrder.status'.tr(),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: MerzoxColors.kColor2B2B2B,
                ),
              ),
              const SizedBox(width: 10),
              _StatusChip(status: order.status),
              const Spacer(),
              if (isSaving)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _KeyValue(label: 'orders.orderNumber'.tr(), value: order.publicId),
          _KeyValue(
            label: 'orders.orderDate'.tr(),
            value: _formatDate(order.createdAt),
          ),
          _KeyValue(
            label: 'merchantOrder.customerName'.tr(),
            value: order.customerName.isEmpty ? '—' : order.customerName,
          ),
          if (order.cancellationReason.isNotEmpty)
            _KeyValue(
              label: 'orders.cancelledReason'.tr(),
              value: order.cancellationReason,
            ),
          if (allowedStatuses.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'merchantOrder.changeStatus'.tr(),
              style: const TextStyle(
                fontSize: 12,
                color: MerzoxColors.kColor767676,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final status in allowedStatuses)
                  OutlinedButton(
                    onPressed: isSaving ? null : () => onStatusSelected(status),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(color: _statusColor(status)),
                      foregroundColor: _statusColor(status),
                    ),
                    child: Text(
                      'merchantOrder.statuses.$status'.tr(),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CourierSection extends StatelessWidget {
  final OwnerOrder order;
  final VoidCallback? onAssign;

  const _CourierSection({required this.order, required this.onAssign});

  @override
  Widget build(BuildContext context) {
    final canAssign =
        onAssign != null && OrderStatusPolicy.canAssignCourier(order.status);

    if (!canAssign && !order.courier.isAssigned) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('tracking.courier'.tr()),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                order.courier.isAssigned
                    ? '${order.courier.name}'
                          '${order.courier.phone.isEmpty ? '' : ' • ${order.courier.phone}'}'
                    : 'merchantOrder.noCourier'.tr(),
                style: const TextStyle(
                  fontSize: 13,
                  color: MerzoxColors.kColor5E5E5E,
                ),
              ),
            ),
            if (canAssign)
              TextButton(
                onPressed: onAssign,
                child: Text(
                  order.courier.isAssigned
                      ? 'common.edit'.tr()
                      : 'merchantOrder.assignCourier'.tr(),
                  style: const TextStyle(
                    color: MerzoxColors.kColorEE6C4D,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  final OwnerOrderItem item;

  const _ItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MerzoxColors.kColorEFEFEF),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: MerzoxColors.kColorF3F7FA,
              borderRadius: BorderRadius.circular(6),
            ),
            child: item.imageUrl.isEmpty
                ? const Icon(
                    Icons.image_outlined,
                    color: MerzoxColors.kColorBEBEBE,
                  )
                : Image.network(
                    item.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.image_outlined,
                      color: MerzoxColors.kColorBEBEBE,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: MerzoxColors.kColor2B2B2B,
                  ),
                ),
                if (item.variant.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.variant,
                    style: const TextStyle(
                      fontSize: 10,
                      color: MerzoxColors.kColor8D99AE,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  '${'orders.quantity'.tr()}: ${item.quantity}'
                  '   •   ${'orders.price'.tr()}: ${_money(item.unitPrice)}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: MerzoxColors.kColor767676,
                  ),
                ),
              ],
            ),
          ),
          Text(
            _money(item.lineTotal),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: MerzoxColors.kColorEE6C4D,
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceSummary extends StatelessWidget {
  final OwnerOrder order;

  const _InvoiceSummary({required this.order});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MerzoxColors.kColorF5F9FC,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MerzoxColors.kColorDEEEF8),
      ),
      child: Column(
        children: [
          _KeyValue(
            label: 'merchantOrder.itemsValue'.tr(),
            value: _money(order.subtotal),
          ),
          _KeyValue(
            label: 'orders.delivery'.tr(),
            value: _money(order.deliveryFee),
          ),
          const Divider(height: 20, color: MerzoxColors.kColorDEEEF8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'merchantOrder.grandTotal'.tr(),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: MerzoxColors.kColor2B2B2B,
                ),
              ),
              Text(
                _money(order.total),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: MerzoxColors.kColorEE6C4D,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InvoiceSheet extends StatelessWidget {
  final OwnerOrder order;
  final String businessName;
  final String businessAddress;

  const _InvoiceSheet({
    required this.order,
    required this.businessName,
    required this.businessAddress,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: MerzoxColors.kColorD8D8D8,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: Text(
                  businessName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: MerzoxColors.kColor2B2B2B,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _KeyValue(
                label: 'merchantOrder.invoiceNumber'.tr(),
                value: order.publicId,
              ),
              _KeyValue(
                label: 'orders.orderDate'.tr(),
                value: _formatDate(order.createdAt),
              ),
              _KeyValue(
                label: 'merchantOrder.customerName'.tr(),
                value: order.customerName.isEmpty ? '—' : order.customerName,
              ),
              _KeyValue(
                label: 'merchantOrder.status'.tr(),
                value: 'merchantOrder.statuses.${order.status}'.tr(),
              ),
              const SizedBox(height: 18),
              _SectionTitle(
                'merchantOrder.products'.tr(args: ['${order.items.length}']),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      'merchantOrder.productName'.tr(),
                      style: _tableHeadStyle,
                    ),
                  ),
                  Expanded(
                    child: Text('orders.price'.tr(), style: _tableHeadStyle),
                  ),
                  Expanded(
                    child: Text('orders.quantity'.tr(), style: _tableHeadStyle),
                  ),
                  Expanded(
                    child: Text(
                      'merchantOrder.lineTotal'.tr(),
                      style: _tableHeadStyle,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
              const Divider(height: 16),
              for (final item in order.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.name, style: _tableCellStyle),
                            if (item.variant.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                item.variant,
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: MerzoxColors.kColor8D99AE,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Expanded(
                        child: Text(
                          _money(item.unitPrice),
                          style: _tableCellStyle,
                        ),
                      ),
                      Expanded(
                        child: Text('${item.quantity}', style: _tableCellStyle),
                      ),
                      Expanded(
                        child: Text(
                          _money(item.lineTotal),
                          style: _tableCellStyle,
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              _SectionTitle('merchantOrder.priceDetails'.tr()),
              const SizedBox(height: 8),
              _InvoiceSummary(order: order),
              const SizedBox(height: 16),
              if (businessAddress.isNotEmpty)
                Text(
                  '${'merchantOrder.storeAddress'.tr()}: $businessAddress',
                  style: const TextStyle(
                    fontSize: 12,
                    color: MerzoxColors.kColor767676,
                  ),
                ),
              const SizedBox(height: 18),
              Center(
                child: Text(
                  'merchantOrder.thanks'.tr(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: MerzoxColors.kColor3D5A80,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: MerzoxColors.kColor2B2B2B,
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  final List<(IconData, String)> lines;

  const _DetailCard({required this.lines});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MerzoxColors.kColorEFEFEF),
      ),
      child: Column(
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Icon(line.$1, size: 16, color: MerzoxColors.kColor8D99AE),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      line.$2,
                      style: const TextStyle(
                        fontSize: 12,
                        color: MerzoxColors.kColor5E5E5E,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  final String label;
  final String value;

  const _KeyValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: MerzoxColors.kColor767676,
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: MerzoxColors.kColor3B3B3B,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        'merchantOrder.statuses.$status'.tr(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

const TextStyle _tableHeadStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w700,
  color: MerzoxColors.kColor767676,
);

const TextStyle _tableCellStyle = TextStyle(
  fontSize: 11,
  color: MerzoxColors.kColor3B3B3B,
);

Color _statusColor(String status) {
  return switch (status) {
    'pending' => MerzoxColors.kColor3D5A80,
    'confirmed' => MerzoxColors.kColor029DD5,
    'preparing' => MerzoxColors.kColorFBB300,
    'outForDelivery' => MerzoxColors.kColorEE6C4D,
    'delivered' => const Color(0xFF2E9B57),
    'cancelled' => MerzoxColors.kColorB72D2D,
    _ => MerzoxColors.kColor8D99AE,
  };
}

String _money(double value) {
  final rounded = value.toStringAsFixed(value % 1 == 0 ? 0 : 2);
  return '$rounded ₪';
}

String _formatDate(DateTime? value) {
  if (value == null) return '—';
  final local = value.toLocal();
  return '${local.day}.${local.month}.${local.year}';
}
