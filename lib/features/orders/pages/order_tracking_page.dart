import 'dart:async';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/features/business_profile/pages/business_profile_page.dart';
import 'package:merzox/features/home/presentation/bloc/home_state_.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/core/localization/api_error_localizer.dart';

import '../bloc/order_tracking_bloc.dart';
import '../bloc/order_tracking_event.dart';
import '../bloc/order_tracking_state.dart';

class OrderTrackingPage extends StatefulWidget {
  const OrderTrackingPage({super.key});

  @override
  State<OrderTrackingPage> createState() => _OrderTrackingPageState();
}

class _OrderTrackingPageState extends State<OrderTrackingPage> {
  /// Raised once per visit, never again after it has been dismissed.
  bool _reviewAsked = false;

  /// `تقييم` is the delivered screen with the review over it.
  ///
  /// Raised rather than pushed to the foot of the page: below a four-step
  /// timeline and a driver's card, an invitation nobody scrolls to is not an
  /// invitation. Dismissing it leaves the same composer at the bottom, so it
  /// is an offer and not a toll.
  void _maybeAskForReview(BuildContext context, OrderTrackingState state) {
    if (_reviewAsked) return;
    if (state.status != OrderTrackingStatus.ready) return;

    final OrderApiModel? order = state.order;
    if (order == null) return;
    if (!order.tracking.canReview || state.reviewSubmitted) return;

    _reviewAsked = true;

    final OrderTrackingBloc bloc = context.read<OrderTrackingBloc>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        // The board dims the screen to #9D9D9D over white, which is black at
        // 98/255 - lighter than Material's own barrier.
        barrierColor: const Color(0x62000000),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => BlocProvider<OrderTrackingBloc>.value(
          value: bloc,
          child: const _ReviewSheet(),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: BlocConsumer<OrderTrackingBloc, OrderTrackingState>(
          listenWhen: (previous, current) =>
              previous.messageCode != current.messageCode ||
              previous.errorMessage != current.errorMessage,
          listener: (context, state) {
            final message = state.errorMessage.isNotEmpty
                ? _translateOrRaw(state.errorMessage)
                : state.messageCode.isNotEmpty
                ? state.messageCode.tr()
                : '';

            if (message.isEmpty) return;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(message)));
          },
          builder: (context, state) {
            // Asked from the builder rather than the listener: a screen opened
            // on an already-delivered order never transitions, so a listener
            // would never hear about it.
            _maybeAskForReview(context, state);

            return Column(
              children: [
                const _TrackingHeader(),
                Expanded(child: _TrackingBody(state: state)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TrackingHeader extends StatelessWidget {
  const _TrackingHeader();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      // Measured against the artboard's title band (y=60..79).
      height: 47,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            'tracking.title'.tr(),
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
    );
  }
}

class _TrackingBody extends StatelessWidget {
  final OrderTrackingState state;

  const _TrackingBody({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.status == OrderTrackingStatus.loading && state.order == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final order = state.order;
    if (order == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 44,
                color: MerzoxColors.kColor8D99AE,
              ),
              const SizedBox(height: 12),
              Text(
                state.errorMessage.isEmpty
                    ? 'tracking.loadError'.tr()
                    : _translateOrRaw(state.errorMessage),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: MerzoxColors.kColor5E5E5E,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => context.read<OrderTrackingBloc>().add(
                  const OrderTrackingRefreshRequested(),
                ),
                child: Text('common.retry'.tr()),
              ),
            ],
          ),
        ),
      );
    }

    final tracking = order.tracking;

    return RefreshIndicator(
      onRefresh: () async => context.read<OrderTrackingBloc>().add(
        const OrderTrackingRefreshRequested(),
      ),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 50, 20, 32),
        children: [
          Text(
            _headlineFor(order),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MerzoxColors.kColor2B2B2B,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _formatFullDate(
              _headlineDate(order),
              context.locale.toLanguageTag(),
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MerzoxColors.kColor767676,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 36),
          _OrderNumberRow(publicId: order.publicId),
          const SizedBox(height: 24),
          if (tracking.isCancelled)
            _CancelledBanner(reason: order.cancellationReason)
          else
            _TrackingTimeline(steps: tracking.steps),
          if (tracking.courier.isAssigned) ...[
            const SizedBox(height: 22),
            _CourierCard(courier: tracking.courier),
          ],
          if (tracking.courierLocation != null) ...[
            const SizedBox(height: 22),
            _CourierLiveMap(location: tracking.courierLocation!),
          ],
          const SizedBox(height: 26),
          _TrackingActions(state: state, order: order),
          if (tracking.canReview && !state.reviewSubmitted) ...[
            const SizedBox(height: 30),
            _ReviewPrompt(busy: state.isBusy),
          ],
        ],
      ),
    );
  }
}

class _OrderNumberRow extends StatelessWidget {
  final String publicId;

  const _OrderNumberRow({required this.publicId});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: MerzoxColors.kColorF9F9F9,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MerzoxColors.kColorEFEFEF),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'orders.orderNumber'.tr(),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: MerzoxColors.kColor3B3B3B,
            ),
          ),
          Text(
            publicId,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: MerzoxColors.kColor2B2B2B,
            ),
          ),
        ],
      ),
    );
  }
}

/// The vertical stepper from the design: a filled dot for every step the order
/// has reached, joined by a rail that only fills as far as the current step.
class _TrackingTimeline extends StatelessWidget {
  final List<OrderTrackingStepApiModel> steps;

  const _TrackingTimeline({required this.steps});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < steps.length; index++)
          _TimelineRow(
            step: steps[index],
            isFirst: index == 0,
            isLast: index == steps.length - 1,
            nextReached: index + 1 < steps.length && steps[index + 1].isReached,
          ),
      ],
    );
  }
}

/// Timeline colours, sampled from the XD `تتبع الطلب` artboard.
const Color _timelineReachedColor = Color(0xFF3D5A80);
const Color _timelinePendingColor = Color(0xFFC0C0C0);
const Color _timelineConnectorColor = Color(0xFFE6E6E6);
const Color _timelineCheckColor = Color(0xFFFAFAFA);

class _TimelineRow extends StatelessWidget {
  final OrderTrackingStepApiModel step;
  final bool isFirst;
  final bool isLast;
  final bool nextReached;

  const _TimelineRow({
    required this.step,
    required this.isFirst,
    required this.isLast,
    required this.nextReached,
  });

  @override
  Widget build(BuildContext context) {
    final reached = step.isReached;
    // Sampled from the artboard: the timeline is navy and grey, not brand
    // orange. Orange is the call-to-action colour on this screen and marking a
    // completed step with it read as an action rather than as progress.
    final activeColor = _timelineReachedColor;
    final idleColor = _timelinePendingColor;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 30,
            child: Column(
              children: [
                Container(
                  width: 3,
                  height: 10,
                  color: isFirst
                      ? Colors.transparent
                      : (reached ? activeColor : _timelineConnectorColor),
                ),
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    // Both states are FILLED discs in the artboard, and both
                    // carry a check. A pending step is a paler disc, not an
                    // empty ring.
                    color: reached ? activeColor : idleColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 12,
                    color: _timelineCheckColor,
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 3,
                    color: isLast
                        ? Colors.transparent
                        : (nextReached ? activeColor : _timelineConnectorColor),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'tracking.steps.${step.step}.title'.tr(),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: reached
                          ? MerzoxColors.kColor2B2B2B
                          : MerzoxColors.kColor9F9F9F,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'tracking.steps.${step.step}.caption'.tr(),
                    style: TextStyle(
                      fontSize: 10,
                      color: reached
                          ? MerzoxColors.kColor767676
                          : MerzoxColors.kColorBEBEBE,
                    ),
                  ),
                  if (step.reachedAt != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      _formatTime(step.reachedAt),
                      style: const TextStyle(
                        fontSize: 10,
                        color: MerzoxColors.kColor8D99AE,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CancelledBanner extends StatelessWidget {
  final String reason;

  const _CancelledBanner({required this.reason});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MerzoxColors.kColorF3B9B9.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MerzoxColors.kColorF3B9B9),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.cancel_outlined,
            size: 34,
            color: MerzoxColors.kColorB72D2D,
          ),
          const SizedBox(height: 10),
          Text(
            'tracking.cancelledTitle'.tr(),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: MerzoxColors.kColorB72D2D,
            ),
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              reason,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                color: MerzoxColors.kColor5E5E5E,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CourierCard extends StatelessWidget {
  final OrderCourierApiModel courier;

  const _CourierCard({required this.courier});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MerzoxColors.kColorF5F9FC,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MerzoxColors.kColorDEEEF8),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 22,
            backgroundColor: MerzoxColors.kColorDEEEF8,
            child: Icon(
              Icons.delivery_dining_rounded,
              color: MerzoxColors.kColor3D5A80,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'tracking.courier'.tr(),
                  style: const TextStyle(
                    fontSize: 11,
                    color: MerzoxColors.kColor767676,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  courier.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: MerzoxColors.kColor2B2B2B,
                  ),
                ),
              ],
            ),
          ),
          if (courier.phone.isNotEmpty)
            Text(
              courier.phone,
              style: const TextStyle(
                fontSize: 12,
                color: MerzoxColors.kColor3D5A80,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

class _CourierLiveMap extends StatefulWidget {
  final OrderCourierLocationApiModel location;

  const _CourierLiveMap({required this.location});

  @override
  State<_CourierLiveMap> createState() => _CourierLiveMapState();
}

class _CourierLiveMapState extends State<_CourierLiveMap> {
  Timer? _expiryTimer;

  bool _expired = false;

  @override
  void initState() {
    super.initState();
    _scheduleExpiry();
  }

  @override
  void didUpdateWidget(covariant _CourierLiveMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.location.capturedAt != widget.location.capturedAt) {
      _scheduleExpiry();
    }
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();

    final now = DateTime.now();

    _expired = !widget.location.isFreshAt(now);

    if (_expired) {
      return;
    }

    final remaining = widget.location.visibleUntil.difference(now);

    _expiryTimer = Timer(remaining + const Duration(milliseconds: 1), () {
      if (!mounted) {
        return;
      }

      setState(() {
        _expired = true;
      });
    });
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_expired || !widget.location.isFreshAt(DateTime.now())) {
      return const SizedBox.shrink();
    }

    final location = widget.location;

    final point = LatLng(location.latitude, location.longitude);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'tracking.liveCourierLocation'.tr(),
          style: const TextStyle(
            color: MerzoxColors.kColor2B2B2B,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: 240,
            child: FlutterMap(
              key: ValueKey(location.capturedAt.microsecondsSinceEpoch),
              options: MapOptions(
                initialCenter: point,
                initialZoom: 16,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.merzox',
                  maxNativeZoom: 19,
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: point,
                      width: 58,
                      height: 58,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: MerzoxColors.kColorEE6C4D,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.delivery_dining_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                  ],
                ),
                RichAttributionWidget(
                  showFlutterMapAttribution: false,
                  attributions: [
                    TextSourceAttribution(
                      'OpenStreetMap contributors',
                      onTap: () => launchUrl(
                        Uri.parse('https://www.openstreetmap.org/copyright'),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TrackingActions extends StatelessWidget {
  final OrderTrackingState state;
  final OrderApiModel order;

  const _TrackingActions({required this.state, required this.order});

  Future<void> _changeAddress(BuildContext context) async {
    final bloc = context.read<OrderTrackingBloc>();
    final controller = TextEditingController(text: order.deliveryAddress);

    final address = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('tracking.changeAddress'.tr()),
        content: TextField(
          controller: controller,
          maxLength: 250,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'tracking.addressHint'.tr(),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text('common.save'.tr()),
          ),
        ],
      ),
    );

    controller.dispose();
    if (address == null || address.isEmpty) return;
    bloc.add(OrderTrackingAddressChanged(address));
  }

  /// The profile bloc refetches the store by id, so an order-sized stub is
  /// enough to open the page the "add more" button points at.
  void _openStore(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BusinessProfilePage(
          business: HomeBusiness(
            id: order.business.id,
            name: order.business.name,
            category: '',
            address: order.business.address,
            products: const [],
            rating: 0,
            colorValue: 0xffdeeef8,
          ),
          onNavChanged: (index) {
            Navigator.of(context).pop();
            context.go('/home?tab=$index');
          },
        ),
      ),
    );
  }

  Future<void> _cancelOrder(BuildContext context) async {
    final bloc = context.read<OrderTrackingBloc>();
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
            child: Text('orders.cancelOrder'.tr()),
          ),
        ],
      ),
    );

    final reason = controller.text.trim();
    controller.dispose();
    if (confirmed != true) return;
    bloc.add(OrderTrackingCancelRequested(reason: reason));
  }

  @override
  Widget build(BuildContext context) {
    final tracking = order.tracking;
    final buttons = <Widget>[];

    if (tracking.canChangeAddress) {
      buttons.add(
        Expanded(
          child: OutlinedButton(
            onPressed: state.isBusy ? null : () => _changeAddress(context),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              side: const BorderSide(color: MerzoxColors.kColor3D5A80),
              foregroundColor: MerzoxColors.kColor3D5A80,
            ),
            child: Text('tracking.changeAddress'.tr()),
          ),
        ),
      );
    }

    if (tracking.canCancel) {
      buttons.add(
        Expanded(
          child: OutlinedButton(
            onPressed: state.isBusy ? null : () => _cancelOrder(context),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              side: const BorderSide(color: MerzoxColors.kColorB72D2D),
              foregroundColor: MerzoxColors.kColorB72D2D,
            ),
            child: Text('orders.cancelOrder'.tr()),
          ),
        ),
      );
    }

    buttons.add(
      Expanded(
        child: FilledButton(
          onPressed: state.isBusy ? null : () => _openStore(context),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
            backgroundColor: MerzoxColors.kColorEE6C4D,
          ),
          child: Text('tracking.addMore'.tr()),
        ),
      ),
    );

    return Row(
      children: [
        for (var index = 0; index < buttons.length; index++) ...[
          if (index > 0) const SizedBox(width: 10),
          buttons[index],
        ],
      ],
    );
  }
}

/// Shown once the order is delivered, matching the "قيم تجربتك للمتجر" block.
/// The review, raised over the delivered order.
class _ReviewSheet extends StatelessWidget {
  const _ReviewSheet();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OrderTrackingBloc, OrderTrackingState>(
      builder: (BuildContext context, OrderTrackingState state) {
        if (state.reviewSubmitted) {
          // Saved: the sheet has nothing left to ask.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          });
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            10,
            16,
            MediaQuery.viewInsetsOf(context).bottom + 50,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 60,
                  height: 4,
                  decoration: BoxDecoration(
                    color: MerzoxColors.kColorEFEFEF,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 22),
                const Icon(
                  Icons.delivery_dining_rounded,
                  size: 90,
                  color: MerzoxColors.kColorEE6C4D,
                ),
                const SizedBox(height: 20),
                _ReviewPrompt(busy: state.isBusy, framed: false),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ReviewPrompt extends StatefulWidget {
  final bool busy;

  /// Whether to draw its own card. False inside the sheet, which is already
  /// one.
  final bool framed;

  const _ReviewPrompt({required this.busy, this.framed = true});

  @override
  State<_ReviewPrompt> createState() => _ReviewPromptState();
}

class _ReviewPromptState extends State<_ReviewPrompt> {
  final TextEditingController _controller = TextEditingController();
  int _rating = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget body = Column(
      crossAxisAlignment: widget.framed
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(
          'tracking.rateTitle'.tr(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: MerzoxColors.kColor2B2B2B,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'tracking.rateHint'.tr(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            height: 1.5,
            color: MerzoxColors.kColor767676,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: widget.framed
              ? MainAxisAlignment.start
              : MainAxisAlignment.center,
          children: [
            for (var star = 1; star <= 5; star++)
              IconButton(
                onPressed: () => setState(() => _rating = star),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                icon: Icon(
                  star <= _rating
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  color: MerzoxColors.kColorFBB300,
                  size: 28,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          maxLines: 3,
          maxLength: 500,
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: Colors.white,
            hintText: 'tracking.reviewHint'.tr(),
            hintStyle: const TextStyle(
              color: MerzoxColors.kColor9F9F9F,
              fontSize: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: MerzoxColors.kColorEFEFEF),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: MerzoxColors.kColorEFEFEF),
            ),
          ),
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: widget.busy || _rating == 0
                ? null
                : () => context.read<OrderTrackingBloc>().add(
                    OrderTrackingReviewSubmitted(
                      rating: _rating,
                      comment: _controller.text,
                    ),
                  ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              backgroundColor: MerzoxColors.kColorEE6C4D,
            ),
            child: Text('common.save'.tr()),
          ),
        ),
      ],
    );

    if (!widget.framed) return body;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MerzoxColors.kColorF9F9F9,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MerzoxColors.kColorEFEFEF),
      ),
      child: body,
    );
  }
}

String _headlineFor(OrderApiModel order) {
  if (order.tracking.isCancelled) return 'tracking.cancelledTitle'.tr();

  return 'tracking.headline.${order.tracking.currentStep}'.tr();
}

DateTime? _headlineDate(OrderApiModel order) {
  final steps = order.tracking.steps.where((step) => step.reachedAt != null);
  if (steps.isEmpty) return order.createdAt;

  return steps.last.reachedAt;
}

String _translateOrRaw(String value) {
  if (value.startsWith('apiErrors.')) {
    return localizeApiErrorOrRaw(value);
  }

  // Existing feature message codes remain translated, while arbitrary
  // backend messages are returned untouched.
  if (!value.contains(' ') && value.contains('.')) return value.tr();
  return value;
}

String _formatTime(DateTime? value) {
  if (value == null) return '';
  final local = value.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final suffix = local.hour >= 12 ? 'PM' : 'AM';

  return '$hour:$minute $suffix';
}

/// The headline date, with the weekday named in [localeName].
///
/// The locale is passed in rather than defaulted: `DateFormat.EEEE()` with no
/// argument resolves to intl's default locale, which is English regardless of
/// what the app is displaying.
String _formatFullDate(DateTime? value, String localeName) {
  if (value == null) return '';
  final local = value.toLocal();
  final weekday = DateFormat.EEEE(localeName).format(local);

  return '$weekday  •  ${local.day}.${local.month}.${local.year} , '
      '${_formatTime(local)}';
}
