import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../models/dashboard_period.dart';

/// The dashboard's search field.
///
/// It was drawn, not built: a `readOnly` `TextField` with a magnifier on it
/// that a merchant could tap all day without anything happening. It searches
/// now, against the order number and the customer name, which is what its own
/// placeholder has always promised.
///
/// The needle is reported after a pause rather than on every keystroke: each
/// report is a request, and a merchant typing an order number would otherwise
/// send eight.
class MerchantOrderSearchField extends StatefulWidget {
  final String initialQuery;
  final ValueChanged<String> onSearch;

  /// How long typing has to stop before the needle is reported.
  final Duration settle;

  const MerchantOrderSearchField({
    required this.initialQuery,
    required this.onSearch,
    this.settle = const Duration(milliseconds: 400),
    super.key,
  });

  @override
  State<MerchantOrderSearchField> createState() =>
      _MerchantOrderSearchFieldState();
}

class _MerchantOrderSearchFieldState extends State<MerchantOrderSearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery,
  );
  Timer? _settling;

  @override
  void dispose() {
    _settling?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _settling?.cancel();
    _settling = Timer(widget.settle, () => widget.onSearch(value.trim()));
    setState(() {});
  }

  void _clear() {
    _settling?.cancel();
    _controller.clear();
    setState(() {});
    widget.onSearch('');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        key: const ValueKey<String>('merchantDashboard.search'),
        controller: _controller,
        textInputAction: TextInputAction.search,
        onChanged: _onChanged,
        // A merchant who presses the keyboard's search key means now, not in
        // four hundred milliseconds.
        onSubmitted: (String value) {
          _settling?.cancel();
          widget.onSearch(value.trim());
        },
        decoration: InputDecoration(
          hintText: 'businessShell.orderSearchHint'.tr(),
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  key: const ValueKey<String>('merchantDashboard.clearSearch'),
                  tooltip: 'businessShell.clearSearch'.tr(),
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: _clear,
                ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// The period control the artboard draws under the search field.
///
/// It reads the period it is on and opens the rest on a tap. `مدى مخصص` hands
/// the merchant the platform's own range picker rather than two separate day
/// pickers, because a range is one decision.
class MerchantPeriodButton extends StatelessWidget {
  final DashboardPeriod period;
  final ValueChanged<DashboardPeriod> onChanged;

  /// Today, for the picker's bounds. Passed rather than read from the clock so
  /// a test can open the picker on a day it chose.
  final DateTime today;

  const MerchantPeriodButton({
    required this.period,
    required this.onChanged,
    required this.today,
    super.key,
  });

  String _label() {
    if (period.kind != DashboardPeriodKind.custom) return period.labelKey.tr();

    final DayRange days = period.boundsOn(today);
    return '${_day(days.from)} - ${_day(days.to)}';
  }

  static String _day(DateTime value) =>
      '${value.day}/${value.month}/${value.year}';

  Future<void> _pickCustom(BuildContext context) async {
    final DayRange current = period.boundsOn(today);

    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      // A shop cannot have orders before it existed, and cannot have them
      // tomorrow, so the picker offers neither.
      firstDate: DateTime(2020),
      lastDate: today,
      initialDateRange: DateTimeRange(start: current.from, end: current.to),
      helpText: 'businessShell.periodPick'.tr(),
    );

    if (picked == null) return;
    onChanged(DashboardPeriod.custom(picked.start, picked.end));
  }

  Future<void> _open(BuildContext context) async {
    final DashboardPeriodKind?
    chosen = await showModalBottomSheet<DashboardPeriodKind>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
              child: Row(
                children: <Widget>[
                  Text(
                    'businessShell.periodTitle'.tr(),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: MerzoxColors.kColor2B2B2B,
                    ),
                  ),
                ],
              ),
            ),
            for (final DashboardPeriod option in DashboardPeriod.selectable)
              ListTile(
                key: ValueKey<String>(
                  'merchantDashboard.period.${option.kind.name}',
                ),
                title: Text(option.labelKey.tr()),
                trailing: option.kind == period.kind
                    ? const Icon(Icons.check_rounded, size: 20)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(option.kind),
              ),
            ListTile(
              key: const ValueKey<String>('merchantDashboard.period.custom'),
              title: Text('businessShell.periodCustom'.tr()),
              trailing: period.kind == DashboardPeriodKind.custom
                  ? const Icon(Icons.check_rounded, size: 20)
                  : const Icon(Icons.date_range_rounded, size: 20),
              onTap: () =>
                  Navigator.of(sheetContext).pop(DashboardPeriodKind.custom),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (chosen == null || !context.mounted) return;

    if (chosen == DashboardPeriodKind.custom) {
      await _pickCustom(context);
      return;
    }

    onChanged(
      DashboardPeriod.selectable.firstWhere(
        (DashboardPeriod option) => option.kind == chosen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      // The board puts this at the trailing edge, under the search field's far
      // side, and the chevron sits past the label rather than before it.
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: FilledButton(
          key: const ValueKey<String>('merchantDashboard.periodButton'),
          onPressed: () => _open(context),
          style: FilledButton.styleFrom(
            backgroundColor: MerzoxColors.kColor98C1D9,
            foregroundColor: MerzoxColors.kColor2B2B2B,
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: Text(
                  _label(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// The pager under the orders table.
///
/// A period of a year can hold thousands of orders, and the table used to show
/// the newest five whatever was asked of it. It shows a page at a time now,
/// and this says which page that is - without which "the last fifty" and "the
/// only fifty" look the same.
class MerchantOrdersPager extends StatelessWidget {
  final int page;
  final int pageCount;
  final int total;
  final bool busy;
  final ValueChanged<int> onPage;

  const MerchantOrdersPager({
    required this.page,
    required this.pageCount,
    required this.total,
    required this.onPage,
    this.busy = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // One page of results needs no controls; the count still tells the
    // merchant how much the period actually holds.
    final bool navigable = pageCount > 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: <Widget>[
          Text(
            'businessShell.ordersInPeriod'.tr(args: <String>['$total']),
            key: const ValueKey<String>('merchantDashboard.orderCount'),
            style: const TextStyle(
              fontSize: 12,
              color: MerzoxColors.kColor8D99AE,
            ),
          ),
          const Spacer(),
          if (navigable) ...<Widget>[
            IconButton(
              key: const ValueKey<String>('merchantDashboard.previousPage'),
              tooltip: 'businessShell.previousPage'.tr(),
              onPressed: busy || page <= 1 ? null : () => onPage(page - 1),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
            Text(
              'businessShell.pageOf'.tr(args: <String>['$page', '$pageCount']),
              key: const ValueKey<String>('merchantDashboard.pageOf'),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: MerzoxColors.kColor2B2B2B,
              ),
            ),
            IconButton(
              key: const ValueKey<String>('merchantDashboard.nextPage'),
              tooltip: 'businessShell.nextPage'.tr(),
              onPressed: busy || page >= pageCount
                  ? null
                  : () => onPage(page + 1),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
          ],
        ],
      ),
    );
  }
}
