import 'dart:async';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:merzox/core/localization/api_error_localizer.dart';
import 'package:merzox/core/constants/money.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/colors.dart';
import '../../authentication/bloc/auth_bloc.dart';
import '../../notifications/widgets/notification_badge_button.dart';
import '../../../injection/injector.dart';
import '../../../services/push_service.dart';
import '../../../services/realtime_service.dart';
import '../models/business_models.dart';
import '../../orders/order_status_policy.dart';
import '../orders/merchant_order_detail_page.dart';
import '../settings/store_settings_page.dart';
import 'package:merzox/features/notification_preferences/bloc/notification_preference_bloc.dart';
import 'package:merzox/features/notification_preferences/bloc/notification_preference_event.dart';
import 'package:merzox/features/notification_preferences/widgets/notification_preference_control.dart';
import 'package:merzox/services/notification_preference_service.dart';
import 'business_bloc.dart';
import 'merchant_alert_bloc.dart';
import 'merchant_browse_widgets.dart';
import 'merchant_filter_sheets.dart';
import 'merchant_product_images_page.dart';

class BusinessShellPage extends StatelessWidget {
  final VoidCallback onLoggedOut;

  /// Injectable so the profile tab's notification switch can be rendered
  /// without a network, which is the only way a golden can capture it.
  final NotificationPreferenceGateway? notificationPreferenceGateway;
  final NotificationPreferenceSessionReader?
  notificationPreferenceSessionReader;

  const BusinessShellPage({
    super.key,
    required this.onLoggedOut,
    this.notificationPreferenceGateway,
    this.notificationPreferenceSessionReader,
  });

  Future<void> _showCourierLocationHandoff(
    BuildContext context,
    CourierLocationHandoff handoff,
  ) async {
    var handedOff = false;

    final expiresAt = handoff.expiresAt.toLocal().toIso8601String();

    final message = 'courierLocation.handoffMessage'.tr(
      args: [handoff.orderId, handoff.capabilityToken, expiresAt],
    );

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => PopScope(
          canPop: handedOff,
          child: AlertDialog(
            title: Text('courierLocation.handoffTitle'.tr()),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('courierLocation.handoffWarning'.tr()),
                const SizedBox(height: 12),
                Text(
                  'courierLocation.handoffOrder'.tr(args: [handoff.orderId]),
                ),
                const SizedBox(height: 6),
                Text('courierLocation.handoffExpires'.tr(args: [expiresAt])),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setDialogState(() {
                    handedOff = true;
                  });
                  Navigator.of(dialogContext).pop();
                },
                child: Text('courierLocation.discardAccess'.tr()),
              ),
              FilledButton.icon(
                onPressed: () async {
                  try {
                    final result = await SharePlus.instance.share(
                      ShareParams(
                        text: message,
                        subject: 'courierLocation.handoffSubject'.tr(),
                        title: 'Merzox',
                      ),
                    );

                    if (!dialogContext.mounted ||
                        result.status == ShareResultStatus.dismissed) {
                      return;
                    }

                    setDialogState(() {
                      handedOff = true;
                    });

                    Navigator.of(dialogContext).pop();
                  } catch (_) {
                    if (!dialogContext.mounted) {
                      return;
                    }

                    ScaffoldMessenger.of(dialogContext)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Text('courierLocation.shareFailed'.tr()),
                        ),
                      );
                  }
                },
                icon: const Icon(Icons.share_outlined),
                label: Text('courierLocation.shareAccess'.tr()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _logout() async {
    if (locator.isRegistered<PushService>()) {
      await locator<PushService>().unregisterCurrentTarget();
    }

    await AuthBloc.clearStoredSession();

    if (locator.isRegistered<RealtimeService>()) {
      await locator<RealtimeService>().disconnect();
    }

    onLoggedOut();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Directionality.of(context),
      child: BlocConsumer<BusinessBloc, BusinessState>(
        listener: (context, state) {
          final handoff = state.courierLocationHandoff;

          if (handoff != null) {
            context.read<BusinessBloc>().add(
              const BusinessCourierLocationHandoffConsumed(),
            );

            unawaited(_showCourierLocationHandoff(context, handoff));
          }

          if (state.status == BusinessStatus.failure &&
              state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(localizeApiErrorOrRaw(state.errorMessage!)),
              ),
            );
          }
        },
        builder: (context, state) {
          if (state.status == BusinessStatus.loading &&
              state.business == null) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (state.business == null) {
            return Scaffold(
              body: _Failure(
                onRetry: () =>
                    context.read<BusinessBloc>().add(const BusinessStarted()),
              ),
            );
          }
          return Scaffold(
            backgroundColor: const Color(0xFFF9FAFC),
            body: SafeArea(
              child: Stack(
                children: <Widget>[
                  switch (state.selectedTab) {
                    0 => _Dashboard(state: state),
                    1 => _Orders(state: state),
                    3 => _Products(state: state),
                    4 => _Profile(
                      state: state,
                      onLogout: _logout,
                      notificationPreferenceGateway:
                          notificationPreferenceGateway,
                      notificationPreferenceSessionReader:
                          notificationPreferenceSessionReader,
                    ),
                    _ => _Dashboard(state: state),
                  },
                  const Positioned(
                    left: 0,
                    right: 0,
                    // Over the list, at the height the artboard draws it.
                    top: 345,
                    child: _AlertBannerHost(),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: _BusinessNavigation(
              selectedIndex: state.selectedTab,
              onChanged: (index) {
                if (index == 2) {
                  _showProductEditor(context);
                } else {
                  context.read<BusinessBloc>().add(BusinessTabChanged(index));
                }
              },
            ),
          );
        },
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _PageHeader({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
    child: Row(
      children: [
        CircleAvatar(
          backgroundColor: Colors.white,
          child: Icon(
            Icons.storefront_rounded,
            color: MerzoxColors.kColor3D5A80,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 12,
                    color: MerzoxColors.kColor8D99AE,
                  ),
                ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'messages.title'.tr(),
          onPressed: () => context.push('/business/messages'),
          icon: const Icon(Icons.chat_bubble_outline_rounded),
        ),
        NotificationBadgeButton(
          tooltip: 'notifications.title'.tr(),
          businessAudience: true,
          onPressed: () => context.push('/notifications?audience=business'),
          iconSize: 24,
          badgeSize: 8,
        ),
      ],
    ),
  );
}

class _Dashboard extends StatelessWidget {
  final BusinessState state;
  const _Dashboard({required this.state});

  @override
  Widget build(BuildContext context) {
    final data = state.dashboard;
    return RefreshIndicator(
      onRefresh: () async {
        context.read<BusinessBloc>().add(const BusinessRefreshed());
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _PageHeader(
            title: 'businessShell.welcome'.tr(args: [state.business!.name]),
            subtitle: 'businessShell.dashboardSummary'.tr(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              readOnly: true,
              decoration: InputDecoration(
                hintText: 'businessShell.orderSearchHint'.tr(),
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _Metric(
                    'businessShell.sales'.tr(),
                    '${data == null ? '0' : merzoxAmount(data.sales)} ₪',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Metric(
                    'businessShell.orders'.tr(),
                    '${data?.orderCount ?? 0}',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Metric(
                    'businessShell.visits'.tr(),
                    '${data?.viewCount ?? 0}',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  'businessShell.latestOrders'.tr(),
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => context.read<BusinessBloc>().add(
                    const BusinessTabChanged(1),
                  ),
                  child: Text('businessShell.more'.tr()),
                ),
              ],
            ),
          ),
          // Measured: the artboard's table header sits at y=393; without this
          // the section heading crowds straight into it 42px early.
          const SizedBox(height: 42),
          if (data == null || data.recentOrders.isEmpty)
            _Empty(message: 'businessShell.noRecentOrders'.tr())
          else
            _RecentOrdersTable(orders: data.recentOrders),
        ],
      ),
    );
  }
}

/// The dashboard's "أحدث الطلبات" summary, as the artboard draws it.
///
/// A table rather than the cards the orders tab uses: a merchant scanning the
/// day's orders reads five short columns faster than five stacked cards, which
/// is presumably why the design puts one here and not there.
class _RecentOrdersTable extends StatelessWidget {
  final List<OwnerOrder> orders;

  /// Null on the dashboard, where the table is a summary; the orders tab
  /// passes a callback so a row opens the order it names.
  final void Function(OwnerOrder order)? onOpen;

  const _RecentOrdersTable({required this.orders, this.onOpen});

  static const double _headerHeight = 48;
  static const double _rowHeight = 37;

  /// The artboard's first row starts 8 below the header, not flush with it.
  static const double _bodyInset = 8;

  /// Column weights, in reading order: number, date, customer, price, status.
  static const List<int> _weights = <int>[4, 4, 4, 2, 4];

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
              height: _headerHeight,
              color: MerzoxColors.kColor3D5A80,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: <Widget>[
                  for (int column = 0; column < headings.length; column++)
                    Expanded(
                      flex: _weights[column],
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
              child: SizedBox(height: _bodyInset, width: double.infinity),
            ),
            for (final OwnerOrder order in orders)
              _OrderRow(order: order, onOpen: onOpen),
          ],
        ),
      ),
    );
  }
}

/// One 37-tall table row.
class _OrderRow extends StatelessWidget {
  final OwnerOrder order;
  final void Function(OwnerOrder order)? onOpen;

  const _OrderRow({required this.order, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final Widget row = SizedBox(
      height: _RecentOrdersTable._rowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: <Widget>[
            _Cell(
              flex: _RecentOrdersTable._weights[0],
              text: '#${order.publicId}',
            ),
            _Cell(
              flex: _RecentOrdersTable._weights[1],
              text: _shortDate(order.createdAt),
            ),
            _Cell(
              flex: _RecentOrdersTable._weights[2],
              text: order.customerName,
            ),
            // The only emphasised value in the row, at 14 bold.
            _Cell(
              flex: _RecentOrdersTable._weights[3],
              text: merzoxAmount(order.total),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            Expanded(
              flex: _RecentOrdersTable._weights[4],
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: _StatusBadge(order.status),
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

class _Cell extends StatelessWidget {
  final int flex;
  final String text;
  final double fontSize;
  final FontWeight fontWeight;

  const _Cell({
    required this.flex,
    required this.text,
    this.fontSize = 11,
    this.fontWeight = FontWeight.w400,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: MerzoxColors.kColor3B3B3B,
        ),
      ),
    );
  }
}

String _shortDate(DateTime? value) {
  if (value == null) return '';
  final DateTime local = value.toLocal();
  return '${local.day}/${local.month}/${local.year}';
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric(this.label, this.value);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: MerzoxColors.kColorDEEEF8),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: MerzoxColors.kColor767676),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

/// The merchant order list, as `الرئيسية – 9` draws it.
///
/// One table holding every status at once, filtered by the chip above it,
/// searched by number or customer name, and narrowed further by the sheet the
/// orange button raises. The segmented current/completed/cancelled control
/// this replaces is not in the design.
class _Orders extends StatelessWidget {
  final BusinessState state;
  const _Orders({required this.state});

  Map<String, String> get _statusLabels => <String, String>{
    for (final String status in _kOrderFilterStatuses)
      status: _statusLabel(status),
  };

  @override
  Widget build(BuildContext context) {
    final BusinessBloc bloc = context.read<BusinessBloc>();
    final MerchantOrderFilter filter = state.orderFilter;

    void apply(MerchantOrderFilter next) =>
        bloc.add(BusinessOrderFilterChanged(next));

    return Column(
      children: <Widget>[
        MerchantTopBar(
          title: 'businessShell.ordersTitle'.tr(),
          leading: NotificationBadgeButton(
            tooltip: 'notifications.title'.tr(),
            businessAudience: true,
            onPressed: () => context.push('/notifications?audience=business'),
            iconSize: 24,
            badgeSize: 8,
          ),
        ),
        const SizedBox(height: kMerchantTopBarToSearch),
        MerchantSearchRow(
          hint: 'businessShell.orderSearchPlaceholder'.tr(),
          onChanged: (String value) => apply(filter.copyWith(query: value)),
          filterIsActive: filter.hasSheetFields,
          onFilterPressed: () async {
            final MerchantOrderFilter? next =
                await showMerchantOrderFilterSheet(
                  context,
                  current: filter,
                  statusLabels: _statusLabels,
                );
            if (next != null) apply(next);
          },
        ),
        const SizedBox(height: kMerchantSearchToSection),
        MerchantSectionRow(
          heading: 'businessShell.allOrders'.tr(),
          trailing: MerchantStatusFilterChip(
            selected: filter.status,
            options: _kOrderFilterStatuses,
            labelOf: _statusLabel,
            onSelected: (String? status) => apply(
              filter.copyWith(status: status, clearStatus: status == null),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => bloc.add(const BusinessRefreshed()),
            child: state.orders.isEmpty
                ? ListView(
                    children: <Widget>[
                      _Empty(message: 'businessShell.noOrders'.tr()),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 20),
                    children: <Widget>[
                      _RecentOrdersTable(
                        orders: state.orders,
                        onOpen: (OwnerOrder order) =>
                            _openOrderDetail(context, state, order),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

/// Shows the newest business notification as `الرئيسية – 17`'s strip, then
/// takes it away again.
///
/// The bloc holds no timer of its own: how long a banner stays up is a
/// presentation decision, so it lives with the widget that presents it.
class _AlertBannerHost extends StatelessWidget {
  const _AlertBannerHost();

  @override
  Widget build(BuildContext context) {
    final RealtimeService? realtime = locator.isRegistered<RealtimeService>()
        ? locator<RealtimeService>()
        : null;

    return BlocProvider<MerchantAlertBloc>(
      create: (_) => MerchantAlertBloc(
        realtimeInvalidations: realtime?.notificationInvalidations,
      )..add(const MerchantAlertStarted()),
      child: const _AlertBanner(),
    );
  }
}

class _AlertBanner extends StatefulWidget {
  const _AlertBanner();

  @override
  State<_AlertBanner> createState() => _AlertBannerHostState();
}

class _AlertBannerHostState extends State<_AlertBanner> {
  static const Duration _visibleFor = Duration(seconds: 5);

  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _dismiss(BuildContext context) {
    _timer?.cancel();
    _timer = null;
    context.read<MerchantAlertBloc>().add(const MerchantAlertDismissed());
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<MerchantAlertBloc, MerchantAlertState>(
      listenWhen: (MerchantAlertState previous, MerchantAlertState current) =>
          previous.message != current.message,
      listener: (BuildContext context, MerchantAlertState state) {
        _timer?.cancel();
        if (state.message == null) return;

        _timer = Timer(_visibleFor, () {
          if (mounted) _dismiss(context);
        });
      },
      builder: (BuildContext context, MerchantAlertState state) {
        final String? message = state.message;

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: message == null
              ? const SizedBox.shrink()
              : MerchantAlertBanner(
                  message: message,
                  onDismissed: () => _dismiss(context),
                ),
        );
      },
    );
  }
}

/// The four statuses `الرئيسية – 11` lists when the chip is open.
///
/// `pending` is deliberately absent: the artboard's menu does not offer it,
/// even though the table below draws new orders with their own chip.
const List<String> _kOrderFilterStatuses = <String>[
  'preparing',
  'outForDelivery',
  'delivered',
  'cancelled',
];

/// Opens the merchant order screen, wiring its actions back to the shell's
/// bloc so a status change refreshes the list the user returns to.
void _openOrderDetail(
  BuildContext context,
  BusinessState state,
  OwnerOrder order,
) {
  final bloc = context.read<BusinessBloc>();

  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => BlocProvider.value(
        value: bloc,
        child: BlocBuilder<BusinessBloc, BusinessState>(
          builder: (innerContext, innerState) {
            final current = innerState.orders
                .where((candidate) => candidate.id == order.id)
                .firstOrNull;

            return MerchantOrderDetailPage(
              order: current ?? order,
              businessName: innerState.business?.name ?? '',
              businessAddress: innerState.business?.address ?? '',
              isSaving: innerState.status == BusinessStatus.saving,
              onStatusSelected: (status) =>
                  bloc.add(BusinessOrderStatusChanged(order.id, status)),
              onCourierAssigned: (name, phone) async => bloc.add(
                BusinessOrderCourierAssigned(
                  orderId: order.id,
                  name: name,
                  phone: phone,
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

class _OrderTile extends StatelessWidget {
  final OwnerOrder order;
  final VoidCallback? onOpen;
  const _OrderTile({required this.order, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final currentStatus = OrderStatusPolicy.isStatus(order.status)
        ? order.status
        : 'pending';
    final options = <String>[
      currentStatus,
      ...OrderStatusPolicy.merchantTransitionsFrom(currentStatus),
    ];

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 5, 16, 7),
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: MerzoxColors.kColorDEEEF8,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.receipt_long_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // AC-28: an absent customer name is stated as unavailable
                    // rather than filled with an invented identity - a merchant
                    // must never read a placeholder as the customer's name.
                    Text(
                      order.customerName.isEmpty
                          ? 'merchantOrder.customerNameUnavailable'.tr()
                          : order.customerName,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontStyle: order.customerName.isEmpty
                            ? FontStyle.italic
                            : FontStyle.normal,
                        color: order.customerName.isEmpty
                            ? MerzoxColors.kColor8D99AE
                            : null,
                      ),
                    ),
                    Text(
                      '#${order.publicId}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      'businessShell.orderSummary'.tr(
                        args: [
                          order.items.length.toString(),
                          merzoxAmount(order.total),
                        ],
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: MerzoxColors.kColor767676,
                      ),
                    ),
                  ],
                ),
              ),
              // Always the editable control now: the dashboard's read-only
              // summary moved to `_RecentOrdersTable`, so this tile is only
              // ever the orders tab, where a merchant changes the status.
              DropdownButton<String>(
                value: currentStatus,
                underline: const SizedBox.shrink(),
                items: options
                    .map(
                      (status) => DropdownMenuItem(
                        value: status,
                        child: Text(_statusLabel(status)),
                      ),
                    )
                    .toList(),
                onChanged: options.length == 1
                    ? null
                    : (status) {
                        if (status != null && status != order.status) {
                          context.read<BusinessBloc>().add(
                            BusinessOrderStatusChanged(order.id, status),
                          );
                        }
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _statusLabel(String status) => switch (status) {
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
const Map<String, Color> _statusColors = <String, Color>{
  'pending': Color(0xFFB9DDF3),
  'confirmed': Color(0xFFB9DDF3),
  'preparing': Color(0xFFF3EBB9),
  'outForDelivery': Color(0xFFC6B9F3),
  'delivered': Color(0xFFBFF3B9),
  'cancelled': Color(0xFFF3B9B9),
};

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge(this.status);
  @override
  Widget build(BuildContext context) => Container(
    width: 58,
    height: 19,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: _statusColors[status] ?? MerzoxColors.kColorDEEEF8,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      _statusLabel(status),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 11, color: MerzoxColors.kColor3B3B3B),
    ),
  );
}

/// The merchant product list, as `الرئيسية – 10` draws it.
///
/// The whole catalogue arrives in one response, so both the search field and
/// `الرئيسية – 16`'s sheet filter it here rather than asking the server for a
/// page it already holds.
class _Products extends StatefulWidget {
  final BusinessState state;
  const _Products({required this.state});

  @override
  State<_Products> createState() => _ProductsState();
}

class _ProductsState extends State<_Products> {
  String _search = '';
  MerchantProductFilter _filter = const MerchantProductFilter();

  static const Map<String, String> _classificationKeys = <String, String>{
    'new': 'merchantProduct.classifications.new',
    'bestSelling': 'merchantProduct.classifications.bestSelling',
    'offers': 'merchantProduct.classifications.offers',
  };

  void _onAction(OwnerProduct product, MerchantProductAction action) {
    final BusinessBloc bloc = context.read<BusinessBloc>();

    switch (action) {
      case MerchantProductAction.edit:
        _showProductEditor(context, product: product);
      case MerchantProductAction.show:
      case MerchantProductAction.hide:
        bloc.add(
          BusinessProductVisibilityChanged(
            productId: product.id,
            visible: action == MerchantProductAction.show,
          ),
        );
      case MerchantProductAction.duplicate:
        bloc.add(BusinessProductDuplicated(product));
      case MerchantProductAction.delete:
        _confirmProductDeletion(context, product);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<OwnerProduct> products = _filter.apply(
      widget.state.products,
      search: _search,
    );
    final bool narrowed = _search.isNotEmpty || !_filter.isEmpty;

    return Column(
      children: <Widget>[
        MerchantTopBar(
          title: 'businessShell.productsHeading'.tr(),
          leading: IconButton(
            tooltip: 'businessShell.addNewProduct'.tr(),
            onPressed: () => _showProductEditor(context),
            icon: const Icon(
              Icons.add_circle_outline_rounded,
              size: 24,
              color: MerzoxColors.kColor98C1D9,
            ),
          ),
        ),
        const SizedBox(height: kMerchantTopBarToSearch),
        MerchantSearchRow(
          hint: 'businessShell.productSearchPlaceholder'.tr(),
          onChanged: (String value) => setState(() => _search = value),
          filterIsActive: !_filter.isEmpty,
          onFilterPressed: () async {
            final MerchantProductFilter? next =
                await showMerchantProductFilterSheet(
                  context,
                  current: _filter,
                  classificationLabels: <String, String>{
                    for (final MapEntry<String, String> entry
                        in _classificationKeys.entries)
                      entry.key: entry.value.tr(),
                  },
                );
            if (next != null) setState(() => _filter = next);
          },
        ),
        const SizedBox(height: kMerchantSearchToSection),
        MerchantSectionRow(
          heading: 'businessShell.allProducts'.tr(),
          trailing: TextButton(
            onPressed: () => _showProductEditor(context),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'businessShell.addNewProduct'.tr(),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: MerzoxColors.kColor9F9F9F,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: products.isEmpty
              ? _Empty(
                  message: 'businessShell.noProducts'.tr(),
                  action: narrowed
                      ? null
                      : FilledButton.icon(
                          onPressed: () => _showProductEditor(context),
                          icon: const Icon(Icons.add),
                          label: Text('businessShell.addProduct'.tr()),
                        ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    kMerchantGutter,
                    0,
                    kMerchantGutter,
                    20,
                  ),
                  itemCount: products.length,
                  itemBuilder: (_, int index) => MerchantProductCard(
                    product: products[index],
                    onOpen: () =>
                        _showProductEditor(context, product: products[index]),
                    onAction: (MerchantProductAction action) =>
                        _onAction(products[index], action),
                  ),
                ),
        ),
      ],
    );
  }
}

/// `الرئيسية – 15` gates deletion behind a yes/no dialog, which the list it
/// replaces did not: a stray tap on the old menu removed a product outright.
Future<void> _confirmProductDeletion(
  BuildContext context,
  OwnerProduct product,
) async {
  final BusinessBloc bloc = context.read<BusinessBloc>();
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      icon: const Icon(
        Icons.error_outline_rounded,
        size: 32,
        color: MerzoxColors.kColorEE6C4D,
      ),
      content: Text(
        'businessShell.deleteProductTitle'.tr(),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: MerzoxColors.kColor2B2B2B,
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: <Widget>[
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: MerzoxColors.kColorEE6C4D,
            fixedSize: const Size(102, 40),
          ),
          child: Text('common.confirm'.tr()),
        ),
        OutlinedButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          style: OutlinedButton.styleFrom(
            foregroundColor: MerzoxColors.kColor2B2B2B,
            fixedSize: const Size(84, 40),
          ),
          child: Text('common.cancel'.tr()),
        ),
      ],
    ),
  );

  if (confirmed ?? false) {
    bloc.add(BusinessProductDeleted(product.id));
  }
}

class _ProductImage extends StatelessWidget {
  final String url;
  const _ProductImage(this.url);
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(7),
    child: SizedBox(
      width: 52,
      height: 52,
      child: url.isEmpty
          ? Container(
              color: MerzoxColors.kColorDEEEF8,
              child: const Icon(Icons.inventory_2_outlined),
            )
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.broken_image_outlined),
            ),
    ),
  );
}

class _Profile extends StatelessWidget {
  final BusinessState state;
  final VoidCallback onLogout;
  final NotificationPreferenceGateway? notificationPreferenceGateway;
  final NotificationPreferenceSessionReader?
  notificationPreferenceSessionReader;

  const _Profile({
    required this.state,
    required this.onLogout,
    this.notificationPreferenceGateway,
    this.notificationPreferenceSessionReader,
  });

  @override
  Widget build(BuildContext context) {
    final OwnerBusiness business = state.business!;

    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        _ProfileHeader(business: business),
        const SizedBox(height: 18),
        _ProfileMenuRow(
          icon: Icons.person_outline_rounded,
          label: 'businessShell.personalProfile'.tr(),
          onTap: () => context.push('/profile/edit'),
        ),
        _ProfileMenuRow(
          icon: Icons.settings_outlined,
          label: 'storeSettings.title'.tr(),
          onTap: () => _showProfileEditor(context, business),
        ),
        _ProfileMenuRow(
          icon: Icons.chat_bubble_outline_rounded,
          label: 'messages.title'.tr(),
          onTap: () => context.push('/business/messages'),
        ),
        _ProfileMenuRow(
          icon: Icons.phone_outlined,
          label: 'businessShell.contactUs'.tr(),
          // The About Us screen carries the company's contact details, which
          // is where a merchant asking for help ends up regardless.
          onTap: () => context.push('/about'),
        ),
        _ProfileMenuRow(
          icon: Icons.visibility_outlined,
          label: 'businessShell.previewStore'.tr(),
          onTap: () => context.push('/business/preview'),
        ),
        _OrderNotificationsRow(
          gateway: notificationPreferenceGateway,
          sessionReader: notificationPreferenceSessionReader,
        ),
        const SizedBox(height: 10),
        _ProfileMenuRow(
          icon: Icons.logout_rounded,
          label: 'businessShell.logout'.tr(),
          onTap: onLogout,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// The band, the logo and the store's name.
class _ProfileHeader extends StatelessWidget {
  final OwnerBusiness business;

  const _ProfileHeader({required this.business});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
          height: 62,
          width: double.infinity,
          color: MerzoxColors.kColor98C1D9,
          alignment: Alignment.center,
          child: Text(
            'businessShell.profileTitle'.tr(),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 18),
        CircleAvatar(
          radius: 26,
          backgroundColor: Colors.white,
          backgroundImage: business.logoUrl.isEmpty
              ? null
              : NetworkImage(business.logoUrl),
          child: business.logoUrl.isNotEmpty
              ? null
              : Text(
                  business.name.isEmpty ? 'M' : business.name.characters.first,
                  style: const TextStyle(
                    fontSize: 20,
                    color: MerzoxColors.kColor3D5A80,
                  ),
                ),
        ),
        const SizedBox(height: 10),
        Text(
          business.name,
          style: const TextStyle(
            fontSize: 13,
            color: MerzoxColors.kColor3B3B3B,
          ),
        ),
      ],
    );
  }
}

/// One menu row: an icon at the trailing edge, a chevron at the leading one.
class _ProfileMenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ProfileMenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Material(
        color: MerzoxColors.kColorF7F8FA,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 48,
            child: Row(
              children: <Widget>[
                const SizedBox(width: 14),
                const Icon(
                  Icons.chevron_left_rounded,
                  size: 20,
                  color: MerzoxColors.kColorBEBEBE,
                ),
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: MerzoxColors.kColor3B3B3B,
                    ),
                  ),
                ),
                Icon(icon, size: 20, color: MerzoxColors.kColor3D5A80),
                const SizedBox(width: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The order-notification switch the artboard puts at the foot of the menu.
///
/// Its own bloc, keyed to the merchant's `orderUpdates`: the customer's
/// marketing switch is a different preference, and a shop owner silencing
/// offers must not silence the notice that an order arrived.
class _OrderNotificationsRow extends StatelessWidget {
  final NotificationPreferenceGateway? gateway;
  final NotificationPreferenceSessionReader? sessionReader;

  const _OrderNotificationsRow({this.gateway, this.sessionReader});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: BlocProvider<NotificationPreferenceBloc>(
        create: (_) => NotificationPreferenceBloc(
          gateway: gateway,
          sessionReader: sessionReader,
          preferenceKey: NotificationPreferenceKeys.orderUpdates,
        )..add(const NotificationPreferenceStarted()),
        child: const NotificationPreferenceControl(
          labelKey: 'businessShell.orderNotifications',
        ),
      ),
    );
  }
}

class _ProfileLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ProfileLine(this.icon, this.text);
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: MerzoxColors.kColor3D5A80),
    title: Text(text.isEmpty ? 'businessShell.unspecified'.tr() : text),
  );
}

class _BusinessNavigation extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  const _BusinessNavigation({
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SizedBox(
      height: 82,
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 14),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Color(0x18000000),
                  blurRadius: 14,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: Row(
              children: [
                _nav(Icons.home_outlined, Icons.home_rounded, 0),
                _nav(
                  Icons.receipt_long_outlined,
                  Icons.receipt_long_rounded,
                  1,
                ),
                const SizedBox(width: 72),
                _nav(Icons.inventory_2_outlined, Icons.inventory_2_rounded, 3),
                _nav(Icons.person_outline_rounded, Icons.person_rounded, 4),
              ],
            ),
          ),
          Positioned(
            top: -4,
            child: InkWell(
              onTap: () => onChanged(2),
              customBorder: const CircleBorder(),
              child: Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: MerzoxColors.kColorEE6C4D,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 5),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x30000000),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.add_rounded,
                  size: 30,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _nav(IconData icon, IconData selectedIcon, int index) => Expanded(
    child: InkWell(
      onTap: () => onChanged(index),
      child: Center(
        child: Icon(
          selectedIndex == index ? selectedIcon : icon,
          color: selectedIndex == index
              ? MerzoxColors.kColorEE6C4D
              : MerzoxColors.kColor8D99AE,
        ),
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  final String message;
  final Widget? action;
  const _Empty({required this.message, this.action});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(42),
    child: Column(
      children: [
        Icon(Icons.inbox_outlined, size: 54, color: MerzoxColors.kColor98C1D9),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}

class _Failure extends StatelessWidget {
  final VoidCallback onRetry;
  const _Failure({required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('businessShell.loadFailed'.tr()),
        const SizedBox(height: 10),
        FilledButton(onPressed: onRetry, child: Text('common.retry'.tr())),
      ],
    ),
  );
}

Future<void> _showProductEditor(
  BuildContext context, {
  OwnerProduct? product,
}) async {
  final bloc = context.read<BusinessBloc>();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        BlocProvider.value(value: bloc, child: _ProductEditor(product)),
  );
}

class _ProductEditor extends StatefulWidget {
  final OwnerProduct? product;
  const _ProductEditor(this.product);
  @override
  State<_ProductEditor> createState() => _ProductEditorState();
}

final class _VariantEditorDraft {
  final String? id;
  final TextEditingController label;
  final TextEditingController priceOverride;
  final TextEditingController costPrice;
  final TextEditingController stockQuantity;

  bool unlimitedStock;
  bool isActive;

  _VariantEditorDraft({
    required this.id,
    required this.label,
    required this.priceOverride,
    required this.costPrice,
    required this.stockQuantity,
    required this.unlimitedStock,
    required this.isActive,
  });

  factory _VariantEditorDraft.empty() {
    return _VariantEditorDraft(
      id: null,
      label: TextEditingController(),
      priceOverride: TextEditingController(),
      costPrice: TextEditingController(),
      stockQuantity: TextEditingController(),
      unlimitedStock: true,
      isActive: true,
    );
  }

  factory _VariantEditorDraft.fromOwner(OwnerProductVariant variant) {
    return _VariantEditorDraft(
      id: variant.id,
      label: TextEditingController(text: variant.label),
      priceOverride: TextEditingController(
        text: variant.priceOverride == null
            ? ''
            : _trimNumber(variant.priceOverride!),
      ),
      costPrice: TextEditingController(
        text: variant.costPrice == null ? '' : _trimNumber(variant.costPrice!),
      ),
      stockQuantity: TextEditingController(
        text: variant.unlimitedStock ? '' : '${variant.stockQuantity}',
      ),
      unlimitedStock: variant.unlimitedStock,
      isActive: variant.isActive,
    );
  }

  double? _optionalDouble(TextEditingController controller) {
    final raw = controller.text.trim();
    return raw.isEmpty ? null : double.parse(raw);
  }

  Map<String, dynamic> toPayload() {
    return OwnerProductVariantDraft(
      id: id,
      label: label.text.trim(),
      priceOverride: _optionalDouble(priceOverride),
      costPrice: _optionalDouble(costPrice),
      stockQuantity: unlimitedStock ? 0 : int.parse(stockQuantity.text.trim()),
      unlimitedStock: unlimitedStock,
      isActive: isActive,
    ).toJson();
  }

  void dispose() {
    label.dispose();
    priceOverride.dispose();
    costPrice.dispose();
    stockQuantity.dispose();
  }
}

class _ProductEditorState extends State<_ProductEditor> {
  static const int _maxVariants = 50;
  static const int _maxVariantLabelLength = 80;

  final _key = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _costPrice;
  late final TextEditingController _stockQuantity;
  late final TextEditingController _discountPercent;
  late final TextEditingController _keywords;
  late final TextEditingController _images;

  late final List<_VariantEditorDraft> _variants;

  late String _classification;
  late bool _isService;
  late bool _isActive;
  late bool _unlimitedStock;
  late bool _hasDiscount;
  late final int _openedAtRevision;

  bool _submitted = false;

  @override
  void initState() {
    super.initState();

    final product = widget.product;

    _name = TextEditingController(text: product?.name ?? '');
    _description = TextEditingController(text: product?.description ?? '');

    _price = TextEditingController(
      text: product == null ? '' : _trimNumber(product.price),
    );

    _costPrice = TextEditingController(
      text: product?.costPrice == null ? '' : _trimNumber(product!.costPrice!),
    );

    _stockQuantity = TextEditingController(
      text: product == null || product.unlimitedStock
          ? ''
          : '${product.stockQuantity}',
    );

    _discountPercent = TextEditingController(
      text: product == null || product.discountPercent <= 0
          ? ''
          : _trimNumber(product.discountPercent),
    );

    _keywords = TextEditingController(
      text: product == null ? '' : product.keywords.join('، '),
    );

    _images = TextEditingController(
      text: product == null ? '' : product.imageUrls.join('\n'),
    );

    _variants =
        product?.variants.map(_VariantEditorDraft.fromOwner).toList() ??
        <_VariantEditorDraft>[];

    _classification = product?.classification ?? 'new';
    _isService = product?.isService ?? false;
    _isActive = product?.isActive ?? true;
    _unlimitedStock = product?.unlimitedStock ?? true;
    _hasDiscount = (product?.discountPercent ?? 0) > 0;

    _openedAtRevision = context.read<BusinessBloc>().state.revision;
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _description,
      _price,
      _costPrice,
      _stockQuantity,
      _discountPercent,
      _keywords,
      _images,
    ]) {
      controller.dispose();
    }

    for (final variant in _variants) {
      variant.dispose();
    }

    super.dispose();
  }

  List<String> _parsedKeywords() => _keywords.text
      .split(RegExp(r'[,،\n]'))
      .map((keyword) => keyword.trim())
      .where((keyword) => keyword.isNotEmpty)
      .toList();

  List<String> _parsedImages() => _images.text
      .split('\n')
      .map((url) => url.trim())
      .where((url) => url.isNotEmpty)
      .toList();

  /// Opens the image manager on the URLs the field currently holds, and
  /// writes back whatever came out of it.
  Future<void> _manageImages() async {
    final List<String>? next = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute<List<String>>(
        builder: (_) => MerchantProductImagesPage(imageUrls: _parsedImages()),
      ),
    );
    if (next == null) return;

    setState(() => _images.text = next.join('\n'));
  }

  void _addVariant() {
    if (_variants.length >= _maxVariants) return;

    setState(() {
      _variants.add(_VariantEditorDraft.empty());
    });
  }

  void _removeVariant(int index) {
    if (index < 0 || index >= _variants.length) return;

    setState(() {
      final removed = _variants.removeAt(index);
      removed.dispose();
    });
  }

  Map<String, dynamic> _buildValues() {
    return {
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'price': double.parse(_price.text.trim()),
      'costPrice': _costPrice.text.trim().isEmpty
          ? null
          : double.parse(_costPrice.text.trim()),
      'unlimitedStock': _unlimitedStock,
      if (!_unlimitedStock)
        'stockQuantity': int.parse(_stockQuantity.text.trim()),
      'discountPercent': _hasDiscount && _discountPercent.text.trim().isNotEmpty
          ? double.parse(_discountPercent.text.trim())
          : 0,
      'keywords': _parsedKeywords(),
      'imageUrls': _parsedImages(),
      'classification': _classification,
      'isService': _isService,
      'isActive': _isActive,

      // Existing variant-mode products explicitly send [] if all variants were
      // removed. New/simple products may omit the variants field completely.
      if (_variants.isNotEmpty || (widget.product?.hasVariants ?? false))
        'variants': _variants.map((variant) => variant.toPayload()).toList(),
    };
  }

  void _submit() {
    if (_submitted) return;
    if (_key.currentState?.validate() != true) return;

    setState(() => _submitted = true);

    context.read<BusinessBloc>().add(
      BusinessProductSaved(
        productId: widget.product?.id,
        values: _buildValues(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<BusinessBloc, BusinessState>(
      listenWhen: (previous, current) =>
          previous.revision != current.revision ||
          previous.status != current.status,
      listener: (context, state) {
        if (!_submitted) return;

        if (state.revision != _openedAtRevision) {
          Navigator.of(context).pop();

          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(content: Text('merchantProduct.saved'.tr())),
            );

          return;
        }

        if (state.status == BusinessStatus.failure) {
          setState(() => _submitted = false);
        }
      },
      builder: (context, state) {
        final saving = _submitted && state.status == BusinessStatus.saving;

        return Directionality(
          textDirection: Directionality.of(context),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              18,
              20,
              MediaQuery.viewInsetsOf(context).bottom + 22,
            ),
            child: SingleChildScrollView(
              child: Form(
                key: _key,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.product == null
                          ? 'merchantProduct.addTitle'.tr()
                          : 'merchantProduct.editTitle'.tr(),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _editorField(
                      _name,
                      'merchantProduct.name'.tr(),
                      hint: 'merchantProduct.nameHint'.tr(),
                    ),
                    _editorField(
                      _description,
                      'merchantProduct.description'.tr(),
                      hint: 'merchantProduct.descriptionHint'.tr(),
                      maxLines: 3,
                      required: false,
                    ),
                    _editorField(
                      _price,
                      'merchantProduct.price'.tr(),
                      keyboardType: TextInputType.number,
                      validator: _positiveNumberValidator,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'merchantProduct.variants'.tr(),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'merchantProduct.variantsHint'.tr(),
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: MerzoxColors.kColor767676,
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _variants.length >= _maxVariants
                          ? null
                          : _addVariant,
                      icon: const Icon(Icons.add),
                      label: Text('merchantProduct.addVariant'.tr()),
                    ),
                    if (_variants.length >= _maxVariants)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'merchantProduct.variantLimit'.tr(),
                          style: TextStyle(
                            fontSize: 11,
                            color: MerzoxColors.kColorEE6C4D,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),

                    if (_variants.isEmpty) ...[
                      _editorField(
                        _costPrice,
                        'merchantProduct.costPrice'.tr(),
                        hint: 'merchantProduct.costPriceHint'.tr(),
                        keyboardType: TextInputType.number,
                        required: false,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? null
                            : _positiveNumberValidator(value),
                      ),
                      SwitchListTile(
                        value: _unlimitedStock,
                        onChanged: (value) {
                          setState(() => _unlimitedStock = value);
                        },
                        title: Text('merchantProduct.unlimited'.tr()),
                        contentPadding: EdgeInsets.zero,
                      ),
                      if (!_unlimitedStock)
                        _editorField(
                          _stockQuantity,
                          'merchantProduct.quantity'.tr(),
                          hint: 'merchantProduct.quantityHint'.tr(),
                          keyboardType: TextInputType.number,
                          validator: _stockValidator,
                        ),
                    ] else ...[
                      for (var index = 0; index < _variants.length; index++)
                        _variantEditorCard(_variants[index], index),
                    ],

                    SwitchListTile(
                      value: _hasDiscount,
                      onChanged: (value) {
                        setState(() => _hasDiscount = value);
                      },
                      title: Text('merchantProduct.hasDiscount'.tr()),
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (_hasDiscount) ...[
                      _editorField(
                        _discountPercent,
                        'merchantProduct.discountPercent'.tr(),
                        keyboardType: TextInputType.number,
                        validator: _discountValidator,
                      ),
                      _DerivedPricePreview(
                        price: _price.text,
                        discountPercent: _discountPercent.text,
                      ),
                    ],
                    DropdownButtonFormField<String>(
                      initialValue: _classification,
                      decoration: InputDecoration(
                        labelText: 'merchantProduct.classification'.tr(),
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'new',
                          child: Text(
                            'merchantProduct.classifications.new'.tr(),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'bestSelling',
                          child: Text(
                            'merchantProduct.classifications.bestSelling'.tr(),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'offers',
                          child: Text(
                            'merchantProduct.classifications.offers'.tr(),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        _classification = value ?? 'new';
                      },
                    ),
                    const SizedBox(height: 12),
                    _editorField(
                      _keywords,
                      'merchantProduct.keywords'.tr(),
                      hint: 'merchantProduct.keywordsHint'.tr(),
                      required: false,
                      validator: (_) => _parsedKeywords().length > 20
                          ? 'merchantProduct.tooManyKeywords'.tr()
                          : null,
                    ),
                    _editorField(
                      _images,
                      'merchantProduct.images'.tr(),
                      hint: 'merchantProduct.imagesHint'.tr(),
                      maxLines: 3,
                      required: false,
                      validator: (_) => _parsedImages().length > 8
                          ? 'merchantProduct.tooManyImages'.tr()
                          : null,
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: _manageImages,
                        icon: const Icon(
                          Icons.photo_library_outlined,
                          size: 18,
                        ),
                        label: Text('merchantImages.manage'.tr()),
                      ),
                    ),
                    SwitchListTile(
                      value: _isService,
                      onChanged: (value) {
                        setState(() => _isService = value);
                      },
                      title: Text('merchantProduct.isService'.tr()),
                      contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile(
                      value: _isActive,
                      onChanged: (value) {
                        setState(() => _isActive = value);
                      },
                      title: Text('merchantProduct.publish'.tr()),
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: saving ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: MerzoxColors.kColorEE6C4D,
                      ),
                      child: Text(
                        saving
                            ? 'merchantProduct.saving'.tr()
                            : 'merchantProduct.save'.tr(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _variantEditorCard(_VariantEditorDraft variant, int index) {
    return Card(
      key: ValueKey('merchant-variant-$index'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'merchantProduct.variantNumber'.tr(args: ['${index + 1}']),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'merchantProduct.removeVariant'.tr(),
                  onPressed: () => _removeVariant(index),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
            _editorField(
              variant.label,
              'merchantProduct.variantLabel'.tr(),
              hint: 'merchantProduct.variantLabelHint'.tr(),
              validator: _variantLabelValidator,
            ),
            _editorField(
              variant.priceOverride,
              'merchantProduct.priceOverride'.tr(),
              hint: 'merchantProduct.priceOverrideHint'.tr(),
              keyboardType: TextInputType.number,
              required: false,
              validator: (value) => value == null || value.trim().isEmpty
                  ? null
                  : _positiveNumberValidator(value),
            ),
            _editorField(
              variant.costPrice,
              'merchantProduct.costPrice'.tr(),
              hint: 'merchantProduct.costPriceHint'.tr(),
              keyboardType: TextInputType.number,
              required: false,
              validator: (value) => value == null || value.trim().isEmpty
                  ? null
                  : _positiveNumberValidator(value),
            ),
            SwitchListTile(
              value: variant.unlimitedStock,
              onChanged: (value) {
                setState(() => variant.unlimitedStock = value);
              },
              title: Text('merchantProduct.unlimited'.tr()),
              contentPadding: EdgeInsets.zero,
            ),
            if (!variant.unlimitedStock)
              _editorField(
                variant.stockQuantity,
                'merchantProduct.quantity'.tr(),
                hint: 'merchantProduct.quantityHint'.tr(),
                keyboardType: TextInputType.number,
                validator: _stockValidator,
              ),
            SwitchListTile(
              value: variant.isActive,
              onChanged: (value) {
                setState(() => variant.isActive = value);
              },
              title: Text('merchantProduct.variantActive'.tr()),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  String? _variantLabelValidator(String? value) {
    final raw = (value ?? '').trim();

    if (raw.isEmpty || raw.length > _maxVariantLabelLength) {
      return 'merchantProduct.invalidVariantLabel'.tr();
    }

    final normalized = raw.toLowerCase();

    final sameLabelCount = _variants
        .where(
          (variant) => variant.label.text.trim().toLowerCase() == normalized,
        )
        .length;

    if (sameLabelCount > 1) {
      return 'merchantProduct.duplicateVariantLabel'.tr();
    }

    return null;
  }

  String? _positiveNumberValidator(String? value) {
    final parsed = double.tryParse((value ?? '').trim());

    if (parsed == null || parsed < 0) {
      return 'merchantProduct.invalidNumber'.tr();
    }

    return null;
  }

  String? _stockValidator(String? value) {
    final parsed = int.tryParse((value ?? '').trim());

    if (parsed == null || parsed < 0) {
      return 'merchantProduct.invalidQuantity'.tr();
    }

    return null;
  }

  String? _discountValidator(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return null;

    final parsed = double.tryParse(raw);

    if (parsed == null || parsed < 0 || parsed > 100) {
      return 'merchantProduct.invalidDiscount'.tr();
    }

    return null;
  }

  Widget _editorField(
    TextEditingController controller,
    String label, {
    String? hint,
    int maxLines = 1,
    bool required = true,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
        validator:
            validator ??
            (value) => required && (value == null || value.trim().isEmpty)
                ? 'merchantProduct.required'.tr()
                : null,
      ),
    );
  }
}

String _trimNumber(double value) => merzoxAmount(value);

/// Shows what the customer will pay. Presentation only - the server recomputes
/// the authoritative final price from the stored base price and discount.
class _DerivedPricePreview extends StatelessWidget {
  final String price;
  final String discountPercent;

  const _DerivedPricePreview({
    required this.price,
    required this.discountPercent,
  });

  @override
  Widget build(BuildContext context) {
    final base = double.tryParse(price.trim());
    final percent = double.tryParse(discountPercent.trim());

    if (base == null || percent == null || percent <= 0 || percent > 100) {
      return const SizedBox.shrink();
    }

    final derived = base * (1 - percent / 100);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        '${'merchantProduct.priceAfterDiscount'.tr()}: '
        '${derived.toStringAsFixed(2)} ₪',
        style: const TextStyle(fontSize: 12, color: MerzoxColors.kColor767676),
      ),
    );
  }
}

Future<void> _showProfileEditor(
  BuildContext context,
  OwnerBusiness business,
) async {
  final bloc = context.read<BusinessBloc>();
  await showDialog<void>(
    context: context,
    builder: (_) =>
        BlocProvider.value(value: bloc, child: _ProfileEditor(business)),
  );
}

class _ProfileEditor extends StatefulWidget {
  final OwnerBusiness business;
  const _ProfileEditor(this.business);
  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.business.name,
  );
  late final TextEditingController _english = TextEditingController(
    text: widget.business.englishName,
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.business.description,
  );
  late final TextEditingController _category = TextEditingController(
    text: widget.business.category,
  );
  late final TextEditingController _address = TextEditingController(
    text: widget.business.address,
  );
  late final TextEditingController _attachment = TextEditingController(
    text: widget.business.attachmentUrl,
  );

  @override
  void dispose() {
    _name.dispose();
    _english.dispose();
    _description.dispose();
    _category.dispose();
    _address.dispose();
    _attachment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: Directionality.of(context),
    child: AlertDialog(
      title: Text('businessShell.editProfile'.tr()),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            children: [
              _field(_name, 'business.storeName'.tr()),
              _field(_english, 'business.englishName'.tr()),
              _field(_description, 'business.description'.tr(), maxLines: 3),
              _field(_category, 'business.category'.tr()),
              _field(_address, 'business.address'.tr()),
              _field(_attachment, 'business.attachmentUrl'.tr()),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          onPressed: () {
            context.read<BusinessBloc>().add(
              BusinessProfileSaved({
                'name': _name.text.trim(),
                'englishName': _english.text.trim(),
                'description': _description.text.trim(),
                'category': _category.text.trim(),
                'address': _address.text.trim(),
                'attachmentUrl': _attachment.text.trim(),
              }),
            );
            Navigator.pop(context);
          },
          child: Text('common.save'.tr()),
        ),
      ],
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );
}
