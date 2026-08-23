import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:merzox/services/review_eligibility_service.dart';

final class ReviewEligibilityNotice extends StatelessWidget {
  final ReviewEligibilityStatus status;
  final bool productTarget;
  final VoidCallback onLogin;
  final VoidCallback onRetry;

  const ReviewEligibilityNotice({
    super.key,
    required this.status,
    required this.productTarget,
    required this.onLogin,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (status == ReviewEligibilityStatus.unchecked ||
        status == ReviewEligibilityStatus.eligible) {
      return const SizedBox.shrink();
    }

    if (status == ReviewEligibilityStatus.checking) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final String message;
    Widget? action;

    switch (status) {
      case ReviewEligibilityStatus.loginRequired:
        message = 'reviews.signInRequired'.tr();
        action = FilledButton(
          onPressed: onLogin,
          child: Text('reviews.signIn'.tr()),
        );

      case ReviewEligibilityStatus.customerAccountRequired:
        message = 'reviews.customerAccountRequired'.tr();

      case ReviewEligibilityStatus.deliveredPurchaseRequired:
        message = productTarget
            ? 'reviews.productDeliveredPurchaseRequired'.tr()
            : 'reviews.deliveredPurchaseRequired'.tr();

      case ReviewEligibilityStatus.failure:
        message = 'reviews.eligibilityCheckFailed'.tr();
        action = OutlinedButton(
          onPressed: onRetry,
          child: Text('common.retry'.tr()),
        );

      case ReviewEligibilityStatus.unchecked:
      case ReviewEligibilityStatus.checking:
      case ReviewEligibilityStatus.eligible:
        return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF5F7FA),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              const Icon(Icons.rate_review_outlined),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13),
              ),
              if (action != null) ...[const SizedBox(height: 10), action],
            ],
          ),
        ),
      ),
    );
  }
}
