import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import '../../../core/constants/dates.dart';
import 'package:flutter/material.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/core/constants/money.dart';
import 'package:merzox/features/business/models/business_models.dart';

/// `تفاصيل الطلب – 3` — the order as a printable invoice.
///
/// A page rather than the sheet it used to be: the board draws a full screen
/// with a printer at the head of it, which is a document, not a summary raised
/// over the screen it came from.
class MerchantOrderInvoicePage extends StatelessWidget {
  final OwnerOrder order;
  final String businessName;
  final String businessAddress;
  final String businessLogoUrl;

  const MerchantOrderInvoicePage({
    super.key,
    required this.order,
    required this.businessName,
    required this.businessAddress,
    this.businessLogoUrl = '',
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: Stack(
                children: <Widget>[
                  const PositionedDirectional(
                    start: 4,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: BackButton(color: MerzoxColors.kColor5E5E5E),
                    ),
                  ),
                  PositionedDirectional(
                    end: 12,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Icon(
                        Icons.print_outlined,
                        size: 22,
                        color: MerzoxColors.kColor5E5E5E,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                children: <Widget>[
                  Center(child: _StoreLogo(url: businessLogoUrl)),
                  const SizedBox(height: 14),
                  Center(
                    child: Text(
                      businessName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: MerzoxColors.kColor2B2B2B,
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  // Two lines of two, not four lines: the board pairs the
                  // invoice number with the date and the customer with the
                  // status, one at each end of the sheet.
                  _HeadRow(
                    start: _HeadLine(
                      label: 'merchantOrder.invoiceNumber'.tr(),
                      value: order.publicId,
                    ),
                    end: _HeadLine(
                      label: 'orders.orderDate'.tr(),
                      value: merzoxDay(order.createdAt),
                    ),
                  ),
                  const SizedBox(height: 9),
                  _HeadRow(
                    start: _HeadLine(
                      label: 'merchantOrder.customerName'.tr(),
                      value: order.customerName.isEmpty
                          ? 'merchantOrder.customerNameUnavailable'.tr()
                          : order.customerName,
                    ),
                    end: _HeadLine(
                      label: 'merchantOrder.status'.tr(),
                      value: 'merchantOrder.statuses.${order.status}'.tr(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Text(
                      'merchantOrder.productsPlain'.tr(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: MerzoxColors.kColor2B2B2B,
                      ),
                    ),
                  ),
                  const SizedBox(height: 13),
                  _ItemsTable(order: order),
                  const SizedBox(height: 26),
                  Center(
                    child: Text(
                      'merchantOrder.priceDetails'.tr(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: MerzoxColors.kColor2B2B2B,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _PriceLine(
                    label: 'merchantOrder.itemsValue'.tr(),
                    value: merzoxAmount(order.subtotal),
                  ),
                  const SizedBox(height: 14),
                  _PriceLine(
                    label: 'orders.delivery'.tr(),
                    value: merzoxAmount(order.deliveryFee),
                  ),
                  const SizedBox(height: 14),
                  _PriceLine(
                    label: 'merchantOrder.grandTotal'.tr(),
                    value: merzoxAmount(order.total),
                    bold: true,
                  ),
                  const SizedBox(height: 24),
                  const _InvoiceRule(),
                  const SizedBox(height: 20),
                  Text(
                    '${'merchantOrder.storeAddress'.tr()}: '
                    '${businessAddress.isEmpty ? '—' : businessAddress}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: MerzoxColors.kColor3B3B3B,
                    ),
                  ),
                  const SizedBox(height: 44),
                  Center(
                    child: Text(
                      'merchantOrder.thanks'.tr(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: MerzoxColors.kColor3D5A80,
                      ),
                    ),
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

class _StoreLogo extends StatelessWidget {
  final String url;

  const _StoreLogo({required this.url});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 82,
      height: 82,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: url.isEmpty
          ? const Icon(
              Icons.storefront_outlined,
              size: 34,
              color: MerzoxColors.kColor98C1D9,
            )
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.storefront_outlined,
                size: 34,
                color: MerzoxColors.kColor98C1D9,
              ),
            ),
    );
  }
}

/// One line of the invoice head: a fact at each end of the sheet.
class _HeadRow extends StatelessWidget {
  final Widget start;
  final Widget end;

  const _HeadRow({required this.start, required this.end});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Flexible(child: start),
        Flexible(child: end),
      ],
    );
  }
}

class _HeadLine extends StatelessWidget {
  final String label;
  final String value;

  const _HeadLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label: $value',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: MerzoxColors.kColor3B3B3B,
      ),
    );
  }
}

/// The four-column table the board draws, under a navy heading row.
class _ItemsTable extends StatelessWidget {
  final OwnerOrder order;

  const _ItemsTable({required this.order});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Table(
        columnWidths: const <int, TableColumnWidth>{
          0: FlexColumnWidth(2.2),
          1: FlexColumnWidth(1.2),
          2: FlexColumnWidth(1.2),
          3: FlexColumnWidth(1.2),
        },
        children: <TableRow>[
          TableRow(
            decoration: const BoxDecoration(color: MerzoxColors.kColor3D5A80),
            children: <Widget>[
              _HeadCell('merchantOrder.productName'.tr()),
              _HeadCell('orders.price'.tr()),
              _HeadCell('orders.quantity'.tr()),
              _HeadCell('merchantOrder.lineTotal'.tr()),
            ],
          ),
          for (final OwnerOrderItem item in order.items)
            TableRow(
              decoration: const BoxDecoration(color: MerzoxColors.kColorF9F9F9),
              children: <Widget>[
                _BodyCell(item.name),
                _BodyCell(merzoxAmount(item.unitPrice)),
                _BodyCell('${item.quantity}'),
                _BodyCell(merzoxAmount(item.lineTotal)),
              ],
            ),
        ],
      ),
    );
  }
}

class _HeadCell extends StatelessWidget {
  final String text;

  const _HeadCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _BodyCell extends StatelessWidget {
  final String text;

  const _BodyCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, color: MerzoxColors.kColor3B3B3B),
      ),
    );
  }
}

class _PriceLine extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _PriceLine({
    required this.label,
    required this.value,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final TextStyle style = TextStyle(
      fontSize: 14,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      color: bold ? MerzoxColors.kColor2B2B2B : MerzoxColors.kColor3B3B3B,
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(label, style: style),
        Text(value, textDirection: TextDirection.ltr, style: style),
      ],
    );
  }
}

class _InvoiceRule extends StatelessWidget {
  const _InvoiceRule();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, color: MerzoxColors.kColorDEEEF8);
  }
}
