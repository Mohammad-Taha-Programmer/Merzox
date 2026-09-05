import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/colors.dart';
import '../../../core/localization/api_error_localizer.dart';
import '../models/business_models.dart';
import '../shell/business_bloc.dart';
import 'merchant_order_detail_page.dart';

/// One order, wired to the merchant's own bloc.
///
/// Extracted from the shell because a notification now opens an order too, and
/// the wiring below is not the sort of thing to keep two copies of: it decides
/// which order is current after a refresh, which actions are dispatched, and
/// how a notice from any of them is shown.
///
/// Requires a [BusinessBloc] above it.
class MerchantOrderDetailView extends StatelessWidget {
  final OwnerOrder order;

  const MerchantOrderDetailView({required this.order, super.key});

  @override
  Widget build(BuildContext context) {
    final BusinessBloc bloc = context.read<BusinessBloc>();

    return BlocConsumer<BusinessBloc, BusinessState>(
      listenWhen: (BusinessState previous, BusinessState current) =>
          previous.noticeCode != current.noticeCode ||
          previous.errorMessage != current.errorMessage,
      listener: (BuildContext innerContext, BusinessState innerState) {
        final String message = (innerState.noticeCode ?? '').isNotEmpty
            ? innerState.noticeCode!.tr()
            : localizeApiErrorOrRaw(innerState.errorMessage ?? '');
        if (message.isEmpty) return;

        ScaffoldMessenger.of(innerContext)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            merchantOrderNoticeSnackBar(
              message,
              isNotice: (innerState.noticeCode ?? '').isNotEmpty,
            ),
          );
      },
      builder: (BuildContext innerContext, BusinessState innerState) {
        // The list is reloaded after every action, so the order in hand is
        // stale the moment one succeeds. The fresh copy wins where there is
        // one; the one this was opened with is the fallback.
        final OwnerOrder? current = innerState.orders
            .where((OwnerOrder candidate) => candidate.id == order.id)
            .firstOrNull;

        return MerchantOrderDetailPage(
          order: current ?? order,
          businessName: innerState.business?.name ?? '',
          businessAddress: innerState.business?.address ?? '',
          businessLogoUrl: innerState.business?.logoUrl ?? '',
          isSaving: innerState.status == BusinessStatus.saving,
          onStatusSelected: (String status) =>
              bloc.add(BusinessOrderStatusChanged(order.id, status)),
          onNotifyCustomer: () =>
              bloc.add(BusinessOrderCustomerNotified(order.id)),
          onCourierAssigned: (String name, String phone) async => bloc.add(
            BusinessOrderCourierAssigned(
              orderId: order.id,
              name: name,
              phone: phone,
            ),
          ),
        );
      },
    );
  }
}

/// One order opened by its id alone, for arrivals from outside the shell.
///
/// A merchant tapping "you have a new order" used to be sent to the customer's
/// tracking screen, which looks that id up among the reader's *own* orders -
/// and a merchant has none, so it said the order did not exist. The order was
/// there the whole time; it was being asked for from the wrong side.
///
/// This owns its own bloc rather than borrowing the shell's, because it is
/// reached by a route and there may be no shell underneath it.
class MerchantOrderRoute extends StatelessWidget {
  final String orderId;

  /// Injected by tests; the route builds its own.
  final BusinessBloc Function()? blocBuilder;

  const MerchantOrderRoute({
    required this.orderId,
    this.blocBuilder,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider<BusinessBloc>(
      create: (_) =>
          (blocBuilder?.call() ?? BusinessBloc())..add(const BusinessStarted()),
      child: BlocBuilder<BusinessBloc, BusinessState>(
        builder: (BuildContext innerContext, BusinessState state) {
          final OwnerOrder? order = state.orders
              .where((OwnerOrder candidate) => candidate.id == orderId)
              .firstOrNull;

          if (order != null) {
            return MerchantOrderDetailView(order: order);
          }

          // Still arriving. Saying "not found" before the list has loaded is
          // how the old screen was wrong, and it is not worth repeating.
          if (state.status == BusinessStatus.initial ||
              state.status == BusinessStatus.loading) {
            return const Scaffold(
              backgroundColor: Colors.white,
              body: Center(child: CircularProgressIndicator()),
            );
          }

          return _NotThisMerchants(
            onRetry: () => innerContext.read<BusinessBloc>().add(
              const BusinessRefreshed(),
            ),
          );
        },
      ),
    );
  }
}

class _NotThisMerchants extends StatelessWidget {
  final VoidCallback onRetry;

  const _NotThisMerchants({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: MerzoxColors.kColor2B2B2B,
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: MerzoxColors.kColor8D99AE,
            ),
            const SizedBox(height: 12),
            Text(
              'merchantOrder.orderNotFound'.tr(),
              key: const ValueKey<String>('merchantOrder.notFound'),
              style: const TextStyle(
                fontSize: 13,
                color: MerzoxColors.kColor767676,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              child: Text('common.retry'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
