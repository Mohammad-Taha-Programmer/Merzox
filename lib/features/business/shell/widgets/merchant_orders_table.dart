import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/constants/dates.dart';
import '../../../../core/constants/money.dart';
import '../../models/business_models.dart';
import 'full_value_dialog.dart';
import 'order_status_presentation.dart';

/// The merchant's latest-orders table, as the artboard draws it.
///
/// A table rather than the cards the orders tab uses: a merchant scanning the
/// day's orders reads five short columns faster than five stacked cards, which
/// is presumably why the design puts one here and not there.
///
/// Five short columns on a phone means text gets cut off, and a cut-off
/// customer name is worse than useless - it looks like data and is not. So a
/// clipped cell is tappable and opens its full value, and the order number
/// answers a long press by going to the clipboard, which is the thing a
/// merchant actually wants to do with an order number.
class MerchantOrdersTable extends StatelessWidget {
  final List<OwnerOrder> orders;

  /// Null on the dashboard, where the table is a summary; the orders tab
  /// passes a callback so a row opens the order it names.
  final void Function(OwnerOrder order)? onOpen;

  const MerchantOrdersTable({required this.orders, this.onOpen, super.key});

  static const double headerHeight = 48;
  static const double rowHeight = 37;

  /// The artboard's first row starts 8 below the header, not flush with it.
  static const double bodyInset = 8;

  /// Column weights, in reading order: number, date, customer, price, status.
  ///
  /// Price takes one more than it did: the column now carries a currency sign
  /// as well as a figure, and at the old weight a three-digit total lost it.
  static const List<int> weights = <int>[4, 4, 4, 3, 4];

  @override
  Widget build(BuildContext context) {
    final List<String> headings = <String>[
      'businessShell.orderNumber'.tr(),
      'businessShell.orderDate'.tr(),
      'businessShell.orderCustomer'.tr(),
      'businessShell.orderPrice'.tr(),
      'businessShell.orderStatus'.tr(),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Column(
          children: <Widget>[
            Container(
              height: headerHeight,
              color: MerzoxColors.kColor3D5A80,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: <Widget>[
                  for (int column = 0; column < headings.length; column++)
                    Expanded(
                      flex: weights[column],
                      child: Text(
                        headings[column],
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const ColoredBox(
              color: MerzoxColors.kColorFDFDFD,
              child: SizedBox(height: bodyInset, width: double.infinity),
            ),
            for (final OwnerOrder order in orders)
              MerchantOrderRow(order: order, onOpen: onOpen),
          ],
        ),
      ),
    );
  }
}

/// One 37-tall table row.
class MerchantOrderRow extends StatelessWidget {
  final OwnerOrder order;
  final void Function(OwnerOrder order)? onOpen;

  const MerchantOrderRow({required this.order, this.onOpen, super.key});

  @override
  Widget build(BuildContext context) {
    final bool rowOwnsTheTap = onOpen != null;

    final Widget row = SizedBox(
      height: MerchantOrdersTable.rowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: <Widget>[
            MerchantOrderCell(
              key: ValueKey<String>('merchantOrders.number.${order.publicId}'),
              flex: MerchantOrdersTable.weights[0],
              text: '#${order.publicId}',
              expandable: !rowOwnsTheTap,
              // The number is the one field a merchant retypes into a message
              // or a search box, so a long press puts it on the clipboard -
              // without the hash, which is decoration this screen added.
              copyValue: order.publicId,
              copiedMessage: 'businessShell.orderNumberCopied'.tr(),
              longPressHint: 'businessShell.holdToCopy'.tr(),
            ),
            MerchantOrderCell(
              flex: MerchantOrdersTable.weights[1],
              // Blank rather than a placeholder: a dense table reads better
              // with a gap than with `--/--/----` in it.
              text: merzoxDay(order.createdAt, whenMissing: ''),
              expandable: !rowOwnsTheTap,
            ),
            MerchantOrderCell(
              key: ValueKey<String>(
                'merchantOrders.customer.${order.publicId}',
              ),
              flex: MerchantOrdersTable.weights[2],
              text: order.customerName,
              expandable: !rowOwnsTheTap,
            ),
            // The only emphasised value in the row, at 14 bold.
            MerchantOrderCell(
              flex: MerchantOrdersTable.weights[3],
              // The figure is money and read as a bare number without this;
              // every other total on the merchant's screens carries the sign.
              text: merzoxPrice(order.total),
              expandable: !rowOwnsTheTap,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            Expanded(
              flex: MerchantOrdersTable.weights[4],
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: MerchantStatusBadge(
                  order.status,
                  expandable: !rowOwnsTheTap,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return ColoredBox(
      color: MerzoxColors.kColorFDFDFD,
      child: onOpen == null
          ? row
          : InkWell(onTap: () => onOpen!(order), child: row),
    );
  }
}

/// One cell, which gives up its full value on demand.
class MerchantOrderCell extends StatelessWidget {
  final int flex;
  final String text;
  final double fontSize;
  final FontWeight fontWeight;

  /// What a long press copies. Null on a cell carrying nothing worth copying,
  /// and then a long press does nothing rather than copying a label.
  final String? copyValue;
  final String? copiedMessage;
  final String? longPressHint;

  /// Whether a tap here opens the full value.
  ///
  /// False on a row that opens the order itself: a cell claiming the tap wins
  /// the gesture arena against the row above it, and the merchant loses the
  /// only way into the order. On such a row the full value is one tap away in
  /// the order itself, so nothing is lost by standing aside. A long press
  /// still copies either way.
  final bool expandable;

  const MerchantOrderCell({
    required this.flex,
    required this.text,
    this.fontSize = 11,
    this.fontWeight = FontWeight.w400,
    this.copyValue,
    this.copiedMessage,
    this.longPressHint,
    this.expandable = true,
    super.key,
  });

  Future<void> _copy(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: copyValue!));

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            copiedMessage ?? 'businessShell.orderNumberCopied'.tr(),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final Widget label = Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: MerzoxColors.kColor3B3B3B,
      ),
    );

    return Expanded(
      flex: flex,
      child: Tooltip(
        message: longPressHint ?? 'businessShell.tapToSeeFull'.tr(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: expandable ? () => showMerchantFullValue(context, text) : null,
          onLongPress: copyValue == null ? null : () => _copy(context),
          child: label,
        ),
      ),
    );
  }
}
