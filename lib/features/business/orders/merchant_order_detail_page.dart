import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/core/constants/money.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/features/business/orders/merchant_order_invoice_page.dart';
import 'package:merzox/features/orders/order_status_policy.dart';

/// `تفاصيل الطلب` — one order, as its four artboards draw it.
///
/// The boards carry no page title: the screen is reached by tapping one row of
/// a list that is already titled, and the order number is the first thing on
/// it.
class MerchantOrderDetailPage extends StatelessWidget {
  final OwnerOrder order;
  final String businessName;
  final String businessAddress;
  final String businessLogoUrl;
  final bool isSaving;

  /// Applying a status is owned by the shell's bloc, so the page reports the
  /// choice upward instead of talking to the API itself.
  final void Function(String status) onStatusSelected;
  final Future<void> Function(String name, String phone)? onCourierAssigned;

  /// `إرسال إشعار`: tell the customer the status again, unchanged.
  final VoidCallback? onNotifyCustomer;

  const MerchantOrderDetailPage({
    super.key,
    required this.order,
    required this.businessName,
    required this.businessAddress,
    required this.onStatusSelected,
    this.businessLogoUrl = '',
    this.onCourierAssigned,
    this.onNotifyCustomer,
    this.isSaving = false,
  });

  List<String> get _allowedStatuses =>
      OrderStatusPolicy.merchantTransitionsFrom(order.status);

  Future<void> _assignCourier(BuildContext context) async {
    final TextEditingController nameController = TextEditingController(
      text: order.courier.name,
    );
    final TextEditingController phoneController = TextEditingController(
      text: order.courier.phone,
    );

    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('merchantOrder.assignCourier'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
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
        actions: <Widget>[
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

    final String name = nameController.text.trim();
    final String phone = phoneController.text.trim();
    nameController.dispose();
    phoneController.dispose();

    if (saved != true || name.isEmpty) return;
    await onCourierAssigned?.call(name, phone);
  }

  void _openInvoice(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MerchantOrderInvoicePage(
          order: order,
          businessName: businessName,
          businessAddress: businessAddress,
          businessLogoUrl: businessLogoUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            const _DetailHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                children: <Widget>[
                  _OrderSummaryBlock(
                    order: order,
                    allowedStatuses: _allowedStatuses,
                    isSaving: isSaving,
                    onStatusSelected: onStatusSelected,
                  ),
                  const _DashedDivider(),
                  _SectionTitle(
                    'merchantOrder.products'.tr(
                      args: <String>['${order.items.length}'],
                    ),
                  ),
                  const SizedBox(height: 14),
                  for (final OwnerOrderItem item in order.items)
                    _ItemRow(item: item, order: order),
                  const SizedBox(height: 17),
                  _SectionTitle('merchantOrder.customerAndDelivery'.tr()),
                  const SizedBox(height: 11),
                  _CustomerBlock(order: order),
                  const SizedBox(height: 20),
                  _SectionTitle('merchantOrder.paymentMethod'.tr()),
                  const SizedBox(height: 8),
                  Text(
                    'merchantOrder.payment.${order.paymentMethod}'.tr(),
                    style: const TextStyle(
                      fontSize: 13,
                      color: MerzoxColors.kColor3B3B3B,
                    ),
                  ),
                  _CourierSection(
                    order: order,
                    onAssign: onCourierAssigned == null
                        ? null
                        : () => _assignCourier(context),
                  ),
                  const _DashedDivider(),
                  _SectionTitle('merchantOrder.invoice'.tr(), fontSize: 15),
                  const SizedBox(height: 12),
                  _InvoiceSummary(order: order),
                  const SizedBox(height: 32),
                  _DetailActionBar(
                    isSaving: isSaving,
                    onNotify: onNotifyCustomer,
                    onViewInvoice: () => _openInvoice(context),
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

/// The bar `تفاصيل الطلب – 2` raises when the customer has been told.
///
/// Built here rather than at the call site so the screen and its confirmation
/// stay one thing: the orange and the bell are part of what `إرسال إشعار`
/// looks like, not of whoever happened to dispatch it.
SnackBar merchantOrderNoticeSnackBar(String message, {bool isNotice = true}) {
  return SnackBar(
    backgroundColor: isNotice ? MerzoxColors.kColorEE6C4D : null,
    behavior: SnackBarBehavior.fixed,
    content: Row(
      children: <Widget>[
        const Icon(
          Icons.notifications_none_rounded,
          size: 20,
          color: Colors.white,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(fontSize: 13, color: Colors.white),
          ),
        ),
      ],
    ),
  );
}

/// Back at the start, the notifications bell at the end, and no title.
class _DetailHeader extends StatelessWidget {
  const _DetailHeader();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: Stack(
        children: <Widget>[
          const PositionedDirectional(
            start: 4,
            top: 0,
            bottom: 0,
            child: Center(child: BackButton(color: MerzoxColors.kColor5E5E5E)),
          ),
          PositionedDirectional(
            end: 12,
            top: 0,
            bottom: 0,
            child: Center(
              child: Icon(
                Icons.notifications_none_rounded,
                size: 22,
                color: MerzoxColors.kColor3D5A80,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The order's number, date and customer on one side, its status control on
/// the other.
class _OrderSummaryBlock extends StatelessWidget {
  final OwnerOrder order;
  final List<String> allowedStatuses;
  final bool isSaving;
  final void Function(String status) onStatusSelected;

  const _OrderSummaryBlock({
    required this.order,
    required this.allowedStatuses,
    required this.isSaving,
    required this.onStatusSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              _SummaryLine(
                label: 'orders.orderNumber'.tr(),
                value: order.publicId,
              ),
              const SizedBox(height: 6),
              _SummaryLine(
                label: 'orders.orderDate'.tr(),
                value: _formatDate(order.createdAt),
              ),
              const SizedBox(height: 6),
              _SummaryLine(
                label: 'merchantOrder.customerName'.tr(),
                value: order.customerName.isEmpty
                    ? 'merchantOrder.customerNameUnavailable'.tr()
                    : order.customerName,
              ),
              if (order.cancellationReason.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                _SummaryLine(
                  label: 'orders.cancelledReason'.tr(),
                  value: order.cancellationReason,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        _StatusControl(
          status: order.status,
          allowedStatuses: allowedStatuses,
          isSaving: isSaving,
          onStatusSelected: onStatusSelected,
        ),
      ],
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label: $value',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.end,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: MerzoxColors.kColor3B3B3B,
      ),
    );
  }
}

/// `حالة الطلب` over the control that changes it.
///
/// The artboards draw a dropdown, not a row of buttons: the statuses an order
/// may move to are a list to choose from, and only one of them can be right.
class _StatusControl extends StatelessWidget {
  final String status;
  final List<String> allowedStatuses;
  final bool isSaving;
  final void Function(String status) onStatusSelected;

  const _StatusControl({
    required this.status,
    required this.allowedStatuses,
    required this.isSaving,
    required this.onStatusSelected,
  });

  @override
  Widget build(BuildContext context) {
    // A new order is outlined and a moved one is filled, which is what the
    // boards draw and what makes "has anyone touched this yet" readable at a
    // glance.
    final bool filled = status != 'pending';
    final bool enabled = allowedStatuses.isNotEmpty && !isSaving;

    final Color ink = filled ? Colors.white : MerzoxColors.kColorEE6C4D;

    final Widget face = Container(
      height: 34,
      width: 104,
      decoration: BoxDecoration(
        color: filled ? MerzoxColors.kColorEE6C4D : Colors.white,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: MerzoxColors.kColorEE6C4D),
      ),
      child: Stack(
        children: <Widget>[
          Center(
            child: Text(
              'merchantOrder.statuses.$status'.tr(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: ink,
              ),
            ),
          ),
          if (enabled)
            PositionedDirectional(
              end: 6,
              top: 0,
              bottom: 0,
              child: Center(
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: ink,
                ),
              ),
            ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'merchantOrder.status'.tr(),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: MerzoxColors.kColor2B2B2B,
          ),
        ),
        const SizedBox(height: 12),
        if (!enabled)
          face
        else
          PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            offset: const Offset(0, 34),
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
              side: const BorderSide(color: MerzoxColors.kColorEE6C4D),
            ),
            onSelected: onStatusSelected,
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              for (final String candidate in allowedStatuses)
                PopupMenuItem<String>(
                  value: candidate,
                  height: 40,
                  child: Center(
                    child: Text(
                      'merchantOrder.statuses.$candidate'.tr(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: MerzoxColors.kColor3B3B3B,
                      ),
                    ),
                  ),
                ),
            ],
            child: face,
          ),
        if (isSaving) ...<Widget>[
          const SizedBox(height: 8),
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: MerzoxColors.kColorEE6C4D,
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  final double fontSize;

  const _SectionTitle(this.text, {this.fontSize = 13});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: MerzoxColors.kColor2B2B2B,
        ),
      ),
    );
  }
}

/// The rule the boards draw between the order's blocks.
class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 17),
      child: CustomPaint(
        size: Size(double.infinity, 1),
        painter: _DashedLinePainter(),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = MerzoxColors.kColorDEEEF8
      ..strokeWidth = 1;

    for (double x = 0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, 0.5), Offset(x + 4, 0.5), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// One line of the order, in the same shape the customer's own list uses.
class _ItemRow extends StatelessWidget {
  final OwnerOrderItem item;
  final OwnerOrder order;

  const _ItemRow({required this.item, required this.order});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: 84,
              height: 84,
              child: item.imageUrl.isEmpty
                  ? Container(
                      color: MerzoxColors.kColorF3F7FA,
                      child: const Icon(
                        Icons.inventory_2_outlined,
                        color: MerzoxColors.kColor98C1D9,
                        size: 28,
                      ),
                    )
                  : Image.network(
                      item.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: MerzoxColors.kColorF3F7FA,
                        child: const Icon(
                          Icons.inventory_2_outlined,
                          color: MerzoxColors.kColor98C1D9,
                          size: 28,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: MerzoxColors.kColor2B2B2B,
                  ),
                ),
                if (item.variant.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    item.variant,
                    style: const TextStyle(
                      fontSize: 10,
                      color: MerzoxColors.kColor8D99AE,
                    ),
                  ),
                ],
                const SizedBox(height: 3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    _Metric(
                      label: 'orders.price'.tr(),
                      value: merzoxAmount(item.unitPrice),
                    ),
                    _Metric(
                      label: 'orders.quantity'.tr(),
                      value: '${item.quantity}',
                    ),
                    _Metric(
                      label: 'orders.delivery'.tr(),
                      value: merzoxAmount(order.deliveryFee),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Align(
                  // The board puts the line's total at the far end of the row,
                  // under the metrics rather than beside the picture.
                  alignment: AlignmentDirectional.centerEnd,
                  child: _TotalChip(
                    label: 'merchantOrder.lineTotal'.tr(),
                    value: merzoxAmount(item.lineTotal + order.deliveryFee),
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

class _Metric extends StatelessWidget {
  final String label;
  final String value;

  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
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

class _TotalChip extends StatelessWidget {
  final String label;
  final String value;

  const _TotalChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 99,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: MerzoxColors.kColor3D5A80,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            textDirection: TextDirection.ltr,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Who ordered, on what number, and where it goes.
class _CustomerBlock extends StatelessWidget {
  final OwnerOrder order;

  const _CustomerBlock({required this.order});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: MerzoxColors.kColorF3F7FA,
          ),
          child: const Icon(
            Icons.person_outline_rounded,
            size: 20,
            color: MerzoxColors.kColor98C1D9,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                order.customerName.isEmpty
                    ? 'merchantOrder.customerNameUnavailable'.tr()
                    : order.customerName,
                style: const TextStyle(
                  fontSize: 13,
                  color: MerzoxColors.kColor3B3B3B,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                order.customerPhone.isEmpty ? '—' : order.customerPhone,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.start,
                style: const TextStyle(
                  fontSize: 13,
                  color: MerzoxColors.kColor3B3B3B,
                ),
              ),
            ],
          ),
        ),
        const Icon(
          Icons.location_on_outlined,
          size: 18,
          color: MerzoxColors.kColor98C1D9,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            order.deliveryAddress.isEmpty ? '—' : order.deliveryAddress,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              color: MerzoxColors.kColor3B3B3B,
            ),
          ),
        ),
      ],
    );
  }
}

class _CourierSection extends StatelessWidget {
  final OwnerOrder order;
  final VoidCallback? onAssign;

  const _CourierSection({required this.order, required this.onAssign});

  @override
  Widget build(BuildContext context) {
    final bool canAssign =
        onAssign != null && OrderStatusPolicy.canAssignCourier(order.status);

    if (!canAssign && !order.courier.isAssigned) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 20),
        _SectionTitle('tracking.courier'.tr()),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                order.courier.isAssigned
                    ? '${order.courier.name}'
                          '${order.courier.phone.isEmpty ? '' : ' • ${order.courier.phone}'}'
                    : 'merchantOrder.noCourier'.tr(),
                style: const TextStyle(
                  fontSize: 13,
                  color: MerzoxColors.kColor3B3B3B,
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

class _InvoiceSummary extends StatelessWidget {
  final OwnerOrder order;

  const _InvoiceSummary({required this.order});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _InvoiceLine(
          label: 'merchantOrder.itemsValue'.tr(),
          value: merzoxAmount(order.subtotal),
        ),
        const SizedBox(height: 17),
        _InvoiceLine(
          label: 'orders.delivery'.tr(),
          value: merzoxAmount(order.deliveryFee),
        ),
        const SizedBox(height: 17),
        _InvoiceLine(
          label: 'merchantOrder.grandTotal'.tr(),
          value: merzoxAmount(order.total),
          bold: true,
        ),
      ],
    );
  }
}

class _InvoiceLine extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _InvoiceLine({
    required this.label,
    required this.value,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: bold ? MerzoxColors.kColor2B2B2B : MerzoxColors.kColor3B3B3B,
          ),
        ),
        Text(
          value,
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontSize: 14,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: bold ? MerzoxColors.kColor2B2B2B : MerzoxColors.kColor3B3B3B,
          ),
        ),
      ],
    );
  }
}

/// `إرسال إشعار` and `عرض الفاتورة` as one 48-tall bar.
class _DetailActionBar extends StatelessWidget {
  final bool isSaving;
  final VoidCallback? onNotify;
  final VoidCallback onViewInvoice;

  const _DetailActionBar({
    required this.isSaving,
    required this.onNotify,
    required this.onViewInvoice,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: <Widget>[
          Expanded(
            child: FilledButton(
              onPressed: isSaving ? null : onNotify,
              style: FilledButton.styleFrom(
                backgroundColor: MerzoxColors.kColorEE6C4D,
                disabledBackgroundColor: MerzoxColors.kColorFEE3DC,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadiusDirectional.horizontal(
                    start: Radius.circular(5),
                  ),
                ),
              ),
              child: Text(
                'merchantOrder.sendNotification'.tr(),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Expanded(
            child: OutlinedButton(
              onPressed: onViewInvoice,
              style: OutlinedButton.styleFrom(
                foregroundColor: MerzoxColors.kColor2B2B2B,
                side: const BorderSide(color: MerzoxColors.kColorCBE0EC),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadiusDirectional.horizontal(
                    end: Radius.circular(5),
                  ),
                ),
              ),
              child: Text(
                'merchantOrder.viewInvoice'.tr(),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime? value) {
  if (value == null) return '--.--.----';
  final DateTime local = value.toLocal();
  return '${local.day}.${local.month}.${local.year}';
}
