import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import 'full_value_dialog.dart';

/// How an order's status is written and coloured wherever a merchant sees it.
///
/// Shared rather than duplicated: the dashboard's table and the orders tab
/// both show the same statuses, and two copies of this would eventually
/// disagree about what `outForDelivery` looks like.
String merchantOrderStatusLabel(String status) => switch (status) {
  'pending' => 'merchantOrder.statuses.pending'.tr(),
  'confirmed' => 'businessShell.statuses.confirmed'.tr(),
  'preparing' => 'merchantOrder.statuses.preparing'.tr(),
  'outForDelivery' => 'merchantOrder.statuses.outForDelivery'.tr(),
  'delivered' => 'merchantOrder.statuses.delivered'.tr(),
  'cancelled' => 'merchantOrder.statuses.cancelled'.tr(),
  _ => status,
};

/// Each status carries its own colour, sampled from the artboard's table.
///
/// One colour for every status made the column decorative; five make it
/// scannable, which is the whole point of showing status in a table.
const Map<String, Color> merchantOrderStatusColors = <String, Color>{
  'pending': Color(0xFFB9DDF3),
  'confirmed': Color(0xFFB9DDF3),
  'preparing': Color(0xFFF3EBB9),
  'outForDelivery': Color(0xFFC6B9F3),
  'delivered': Color(0xFFBFF3B9),
  'cancelled': Color(0xFFF3B9B9),
};

class MerchantStatusBadge extends StatelessWidget {
  final String status;

  /// Whether a tap here opens the full label.
  ///
  /// False on a row that opens the order itself: a badge claiming the tap
  /// wins the gesture arena against the row above it. Same rule the cells
  /// beside it follow.
  final bool expandable;

  const MerchantStatusBadge(this.status, {this.expandable = true, super.key});

  @override
  Widget build(BuildContext context) {
    final String label = merchantOrderStatusLabel(status);

    // 58 wide at the artboard's size, which is narrower than the longest
    // status the app can show, so this one is cut more often than any cell in
    // the row: `تم التسليم` becomes `تم التسل...`.
    final Widget badge = Container(
      width: 58,
      height: 19,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: merchantOrderStatusColors[status] ?? MerzoxColors.kColorDEEEF8,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, color: MerzoxColors.kColor3B3B3B),
      ),
    );

    return Tooltip(
      message: 'businessShell.tapToSeeFull'.tr(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: expandable ? () => showMerchantFullValue(context, label) : null,
        child: badge,
      ),
    );
  }
}
