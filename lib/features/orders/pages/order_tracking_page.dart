import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/features/business_profile/pages/business_profile_page.dart';
import 'package:merzox/features/home/presentation/bloc/home_state_.dart';
import 'package:merzox/services/api_service.dart';

import '../bloc/order_tracking_bloc.dart';
import '../bloc/order_tracking_event.dart';
import '../bloc/order_tracking_state.dart';

class OrderTrackingPage extends StatelessWidget {
  const OrderTrackingPage({super.key});

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
      height: 66,
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
                    : state.errorMessage,
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
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 32),
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
            _formatFullDate(_headlineDate(order)),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MerzoxColors.kColor767676,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 22),
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
    final activeColor = MerzoxColors.kColorEE6C4D;
    final idleColor = MerzoxColors.kColorD8D8D8;

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
                      : (reached ? activeColor : idleColor),
                ),
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: reached ? activeColor : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: reached ? activeColor : idleColor,
                      width: 2,
                    ),
                  ),
                  child: reached
                      ? const Icon(
                          Icons.check_rounded,
                          size: 12,
                          color: Colors.white,
                        )
                      : null,
                ),
                Expanded(
                  child: Container(
                    width: 3,
                    color: isLast
                        ? Colors.transparent
                        : (nextReached ? activeColor : idleColor),
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
class _ReviewPrompt extends StatefulWidget {
  final bool busy;

  const _ReviewPrompt({required this.busy});

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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MerzoxColors.kColorF9F9F9,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MerzoxColors.kColorEFEFEF),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'tracking.rateTitle'.tr(),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: MerzoxColors.kColor2B2B2B,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'tracking.rateHint'.tr(),
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: MerzoxColors.kColor767676,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var star = 1; star <= 5; star++)
                IconButton(
                  onPressed: () => setState(() => _rating = star),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 38,
                    minHeight: 38,
                  ),
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
      ),
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
  // Bloc failures arrive as either a translation key or a server message.
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

String _formatFullDate(DateTime? value) {
  if (value == null) return '';
  final local = value.toLocal();
  final weekday = DateFormat.EEEE().format(local);

  return '$weekday  •  ${local.day}.${local.month}.${local.year} , '
      '${_formatTime(local)}';
}
