import '../../../core/auth/role_switch_service.dart';
import '../../../core/widgets/remote_circle_avatar.dart';
import '../../messages/widgets/message_badge.dart';
import '../../notifications/widgets/global_notification_bell.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:merzox/core/localization/api_error_localizer.dart';
import 'package:merzox/core/constants/money.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/colors.dart';
import '../../authentication/bloc/auth_bloc.dart';
import '../../../injection/injector.dart';
import '../../../services/push_service.dart';
import '../../../services/realtime_service.dart';
import 'package:merzox/features/business/products/merchant_product_editor_page.dart';
import 'package:merzox/features/business/shell/business_navigation_bar.dart';
import '../models/business_models.dart';
import '../models/dashboard_period.dart';
import 'widgets/merchant_avatar_button.dart';
import 'widgets/merchant_dashboard_controls.dart';
import 'widgets/merchant_orders_table.dart';
import 'widgets/order_status_presentation.dart';
import '../orders/merchant_order_route.dart';
import '../settings/store_settings_page.dart';
import 'package:merzox/features/notification_preferences/bloc/notification_preference_bloc.dart';
import 'package:merzox/features/notification_preferences/bloc/notification_preference_event.dart';
import 'package:merzox/features/notification_preferences/widgets/notification_preference_control.dart';
import 'package:merzox/services/notification_preference_service.dart';
import 'business_bloc.dart';
import 'merchant_alert_bloc.dart';
import 'merchant_browse_widgets.dart';
import 'merchant_filter_sheets.dart';

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
    final BusinessBloc bloc = context.read<BusinessBloc>();

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
                  // `تجاهل الرمز` said the credential was discarded while
                  // leaving it live until the order moved on. It is minted and
                  // shown once, so discarding has to reach the server.
                  bloc.add(BusinessCourierLocationRevoked(handoff.orderId));
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
                    0 => _Dashboard(state: state, onLogout: _logout),
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
                    _ => _Dashboard(state: state, onLogout: _logout),
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
            bottomNavigationBar: BusinessNavigationBar(
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
  /// The shop's name, plainly.
  ///
  /// It used to be wrapped in a greeting with a line under it summarising what
  /// the screen was - two sentences telling the merchant things they knew,
  /// above the figures they had opened the app to read.
  final String title;

  /// The account's picture. Empty draws the placeholder glyph the bar used to
  /// draw for everyone.
  final String avatarUrl;

  /// Signs the merchant out. It lives in the profile tab too; here it is the
  /// outermost control in the bar, past the bell, so the destructive one is
  /// the hardest of the three to reach by accident.
  final VoidCallback? onLogout;

  const _PageHeader({required this.title, this.avatarUrl = '', this.onLogout});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
    child: Row(
      children: [
        MerchantAvatarButton(
          avatarUrl: avatarUrl,
          onPicked: (Uint8List bytes) async =>
              context.read<BusinessBloc>().add(BusinessAvatarPicked(bytes)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
        IconButton(
          tooltip: 'messages.title'.tr(),
          onPressed: () => context.push('/business/messages'),
          icon: const MessageBadge(
            businessAudience: true,
            child: Icon(Icons.chat_bubble_outline_rounded),
          ),
        ),
        if (onLogout case final VoidCallback signOut)
          IconButton(
            key: const ValueKey<String>('merzox.businessShell.logout'),
            tooltip: 'businessShell.logout'.tr(),
            onPressed: signOut,
            icon: const Icon(
              Icons.logout_rounded,
              size: 24,
              color: MerzoxColors.kColor8D99AE,
            ),
          ),
        // The floating bell owns this corner on every screen, so the bar
        // leaves it free rather than being drawn under it.
        const SizedBox(width: kGlobalBellReservedWidth),
      ],
    ),
  );
}

class _Dashboard extends StatelessWidget {
  final BusinessState state;
  final VoidCallback onLogout;

  const _Dashboard({required this.state, required this.onLogout});

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
            title: state.business!.name,
            avatarUrl: state.account?.avatarUrl ?? '',
            onLogout: onLogout,
          ),
          MerchantOrderSearchField(
            initialQuery: state.dashboardQuery,
            onSearch: (String query) => context.read<BusinessBloc>().add(
              BusinessDashboardSearchChanged(query),
            ),
          ),
          const SizedBox(height: 14),
          MerchantPeriodButton(
            period: state.dashboardPeriod,
            today: DateTime.now(),
            onChanged: (DashboardPeriod period) => context
                .read<BusinessBloc>()
                .add(BusinessDashboardPeriodChanged(period)),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _Metric(
                    'businessShell.sales'.tr(),
                    data == null ? merzoxPrice(0) : merzoxPrice(data.sales),
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
                    // Sales and orders answer to the period above; visits are
                    // a running counter with no dates behind it, so the card
                    // says which of the two it is rather than letting the
                    // merchant assume.
                    footnote: 'businessShell.visitsAllTime'.tr(),
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
          if (state.dashboardBusy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (state.dashboardOrders.isEmpty)
            _Empty(message: 'businessShell.noOrdersInPeriod'.tr())
          else
            MerchantOrdersTable(orders: state.dashboardOrders),
          if (!state.dashboardBusy && state.dashboardOrders.isNotEmpty)
            MerchantOrdersPager(
              page: state.dashboardPage,
              pageCount: state.dashboardPageCount,
              total: state.dashboardOrderTotal,
              busy: state.dashboardBusy,
              onPage: (int page) => context.read<BusinessBloc>().add(
                BusinessDashboardPageChanged(page),
              ),
            ),
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

/// One 37-tall table row.

class _Metric extends StatelessWidget {
  final String label;
  final String value;

  /// A quieter line under the figure, for a card whose figure does not mean
  /// the same thing as its neighbours'.
  final String? footnote;

  const _Metric(this.label, this.value, {this.footnote});

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
        if (footnote case final String note) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            note,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 9, color: MerzoxColors.kColor8D99AE),
          ),
        ],
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

  Map<String, String> get merchantOrderStatusLabels => <String, String>{
    for (final String status in _kOrderFilterStatuses)
      status: merchantOrderStatusLabel(status),
  };

  @override
  Widget build(BuildContext context) {
    final BusinessBloc bloc = context.read<BusinessBloc>();
    final MerchantOrderFilter filter = state.orderFilter;

    void apply(MerchantOrderFilter next) =>
        bloc.add(BusinessOrderFilterChanged(next));

    return Column(
      children: <Widget>[
        MerchantTopBar(title: 'businessShell.ordersTitle'.tr()),
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
                  statusLabels: merchantOrderStatusLabels,
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
            labelOf: merchantOrderStatusLabel,
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
                      MerchantOrdersTable(
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

/// Opens the merchant order screen on top of the shell.
///
/// The screen itself and its wiring live in [MerchantOrderDetailView], which a
/// notification arriving from outside the shell opens by id through the same
/// code rather than a second copy of it.
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
        child: MerchantOrderDetailView(order: order),
      ),
    ),
  );
}

/// Each status carries its own colour, sampled from the artboard's table.
///
/// One colour for every status made the column decorative; five make it
/// scannable, which is the whole point of showing status in a table.

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
        confirmProductDeletion(context, product);
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

    // The board draws a blue field with a white sheet lifted onto it, and
    // everything below the name lives on that sheet. Drawn as one scrolling
    // list so a taller font or a shorter phone moves the sheet rather than
    // clipping it.
    return Stack(
      children: <Widget>[
        Container(
          height: kProfileFieldHeight,
          width: double.infinity,
          color: MerzoxColors.kColor98C1D9,
        ),
        ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            const _ProfileHeader(),
            _ProfileSheet(
              children: <Widget>[
                _ProfileIdentity(
                  business: business,
                  onRegisterAsCustomer: () async {
                    // The same account, used the other way round: a shopkeeper
                    // buying from another shopkeeper. Nothing is signed out.
                    await const RoleSwitchService().actAsCustomer();
                    if (context.mounted) context.go('/home');
                  },
                ),
                MerchantProfileMenuRow(
                  icon: Icons.person_outline_rounded,
                  label: 'businessShell.personalProfile'.tr(),
                  showChevron: true,
                  onTap: () => context.push('/profile/edit'),
                ),
                MerchantProfileMenuRow(
                  icon: Icons.settings_outlined,
                  label: 'storeSettings.title'.tr(),
                  showChevron: true,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => BlocProvider<BusinessBloc>.value(
                        value: context.read<BusinessBloc>(),
                        child: StoreSettingsPage(business: business),
                      ),
                    ),
                  ),
                ),
                MerchantProfileMenuRow(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'messages.title'.tr(),
                  showChevron: true,
                  onTap: () => context.push('/business/messages'),
                ),
                // The board drops the chevron from here down: these three do
                // not open a screen with more of the same behind it.
                MerchantProfileMenuRow(
                  icon: Icons.phone_outlined,
                  label: 'businessShell.contactUs'.tr(),
                  // The About Us screen carries the company's contact details,
                  // which is where a merchant asking for help ends up anyway.
                  onTap: () => context.push('/about'),
                ),
                MerchantProfileMenuRow(
                  icon: Icons.visibility_outlined,
                  label: 'businessShell.previewStore'.tr(),
                  onTap: () => context.push('/business/preview'),
                ),
                _OrderNotificationsRow(
                  gateway: notificationPreferenceGateway,
                  sessionReader: notificationPreferenceSessionReader,
                ),
                const SizedBox(height: kProfileRowGap),
                _ProfileLogoutButton(onPressed: onLogout),
                const SizedBox(height: 28),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// The board's own measurements for this screen.
const double kProfileFieldHeight = 290;
const double kProfileSheetTop = 113;
const double kProfileSheetRadius = 20;
const double kProfileGutter = 16;
const double kProfileRowHeight = 48;
const double kProfileRowRadius = 6;
const double kProfileRowGap = 16;
const double kProfileAvatarDiameter = 37;
const double kProfileAvatarRing = 5;

/// The white sheet the menu sits on, lifted onto the blue field.
class _ProfileSheet extends StatelessWidget {
  final List<Widget> children;

  const _ProfileSheet({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(kProfileSheetRadius),
        ),
      ),
      child: Column(children: children),
    );
  }
}

/// `تسجيل خروج`, which the board draws as a narrow pill rather than a row.
class _ProfileLogoutButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _ProfileLogoutButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: MerzoxColors.kColorF5F9FC,
        borderRadius: BorderRadius.circular(kProfileRowRadius),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(kProfileRowRadius),
          child: Container(
            width: 162,
            constraints: const BoxConstraints(minHeight: kProfileRowHeight),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Icon(
                  Icons.logout_rounded,
                  size: 20,
                  color: MerzoxColors.kColor3D5A80,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'businessShell.logout'.tr(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF292828),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The band, the logo and the store's name.
/// The blue field's title, and the strip of blue under it that the sheet is
/// lifted onto.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        // The blue field runs behind the status bar on the board, so the title
        // sits under whatever the device reserves there rather than at a fixed
        // offset from the top of the app.
        SizedBox(
          height: kProfileTitleBand,
          width: double.infinity,
          child: Center(
            child: Text(
              'businessShell.profileTitle'.tr(),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: kProfileSheetGap),
      ],
    );
  }
}

/// The picture, the name and the customer button, which stand on the sheet.
class _ProfileIdentity extends StatelessWidget {
  final OwnerBusiness business;
  final Future<void> Function() onRegisterAsCustomer;

  const _ProfileIdentity({
    required this.business,
    required this.onRegisterAsCustomer,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        const SizedBox(height: 30),
        // A ring of the field's own blue, which is what sets the picture off
        // from the white it sits on.
        Container(
          padding: const EdgeInsets.all(kProfileAvatarRing),
          decoration: const BoxDecoration(
            color: MerzoxColors.kColor98C1D9,
            shape: BoxShape.circle,
          ),
          child: RemoteCircleAvatar(
            url: business.logoUrl,
            radius: kProfileAvatarDiameter / 2,
            backgroundColor: Colors.white,
            fallback: Text(
              business.name.isEmpty ? 'M' : business.name.characters.first,
              style: const TextStyle(
                fontSize: 16,
                color: MerzoxColors.kColor3D5A80,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          business.name,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: MerzoxColors.kColor2B2B2B,
          ),
        ),
        const SizedBox(height: 16),
        RegisterAsCustomerButton(onPressed: onRegisterAsCustomer),
        const SizedBox(height: 25),
      ],
    );
  }
}

/// The band the title sits in, under the status bar.
const double kProfileTitleBand = 44;

/// The strip of blue between the title and the sheet.
///
/// The board leaves 25 here, which put the sheet's edge at 113. Widened on the
/// reader's eye: they wanted more blue above the picture than the board gives,
/// and the numbers below it keep the board's own spacing rather than being
/// squeezed to hold the rows at their original marks.
const double kProfileSheetGap = 45;

/// `التسجيل كزبون`, the mirror of the customer profile's `التسجيل كتاجر`.
/// The button that turns the shopkeeper into a customer.
///
/// Nothing is signed out and no second account is made: the same login, used
/// the other way round, so a shopkeeper can buy from another shop. Public so
/// the turn can be exercised without standing up the whole shell.
class RegisterAsCustomerButton extends StatelessWidget {
  final Future<void> Function() onPressed;

  const RegisterAsCustomerButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MerzoxColors.kColor3D5A80,
      borderRadius: BorderRadius.circular(kProfileRowRadius),
      child: InkWell(
        onTap: () => onPressed(),
        borderRadius: BorderRadius.circular(kProfileRowRadius),
        child: Container(
          width: 182,
          constraints: const BoxConstraints(minHeight: kProfileRowHeight),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(
                Icons.person_outline_rounded,
                size: 20,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  'businessShell.registerAsCustomer'.tr(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
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

/// One menu row: an icon at the trailing edge, a chevron at the leading one.
/// One row of the merchant profile menu.
///
/// Public so its two board rules can be stated in a test: the icon stands at
/// the reading edge with the words beside it, and the chevron is kept for the
/// rows that open a screen with more of the same behind them.
class MerchantProfileMenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// The board keeps the chevron for the rows that open a screen with more of
  /// the same behind it, and drops it from the ones that do a single thing.
  final bool showChevron;

  const MerchantProfileMenuRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.showChevron = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kProfileGutter,
        0,
        kProfileGutter,
        kProfileRowGap,
      ),
      child: Material(
        color: MerzoxColors.kColorF5F9FC,
        borderRadius: BorderRadius.circular(kProfileRowRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(kProfileRowRadius),
          child: Container(
            // A floor, not a fixed height: a reader who turns the system font
            // up needs the row to grow rather than clip.
            constraints: const BoxConstraints(minHeight: kProfileRowHeight),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: <Widget>[
                // The board sets the icon at the reading edge with the words
                // beside it, and the chevron alone at the far end.
                Icon(icon, size: 20, color: MerzoxColors.kColor3D5A80),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: MerzoxColors.kColor2B2B2B,
                    ),
                  ),
                ),
                if (showChevron)
                  const Icon(
                    Icons.chevron_left_rounded,
                    size: 20,
                    color: MerzoxColors.kColor3D5A80,
                  ),
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
      padding: const EdgeInsets.symmetric(horizontal: kProfileGutter),
      child: BlocProvider<NotificationPreferenceBloc>(
        create: (_) => NotificationPreferenceBloc(
          gateway: gateway,
          sessionReader: sessionReader,
          preferenceKey: NotificationPreferenceKeys.orderUpdates,
        )..add(const NotificationPreferenceStarted()),
        // Sized to stand in line with the rows above it on this board.
        child: const NotificationPreferenceControl(
          labelKey: 'businessShell.orderNotifications',
          height: kProfileRowHeight,
          cornerRadius: kProfileRowRadius,
          gap: kProfileRowGap,
        ),
      ),
    );
  }
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

/// Opens `إضافة منتجات`.
///
/// A route rather than a sheet: the artboards are 1334 tall with the shell's
/// own bar drawn across the fold, which is a full screen the form scrolls
/// inside, not a sheet raised over the list.
Future<void> _showProductEditor(
  BuildContext context, {
  OwnerProduct? product,
}) async {
  final BusinessBloc bloc = context.read<BusinessBloc>();

  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => BlocProvider<BusinessBloc>.value(
        value: bloc,
        child: MerchantProductEditorPage(
          product: product,
          onTabRequested: (int index) => bloc.add(BusinessTabChanged(index)),
        ),
      ),
    ),
  );
}

/// Shows what the customer will pay. Presentation only - the server recomputes
/// the authoritative final price from the stored base price and discount.
