import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/features/business/shell/business_bloc.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_bloc.dart';
import 'package:merzox/features/business_profile/business_profile_view_mode.dart';
import 'package:merzox/features/business_profile/pages/business_profile_page.dart';
import 'package:merzox/features/home/presentation/bloc/home_state_.dart';
import 'package:merzox/core/localization/api_error_localizer.dart';

/// "معاينة المتجر" - the merchant's own store, shown exactly as customers see
/// it.
///
/// This page owns almost no presentation. It resolves *which* business to show
/// from the authenticated merchant session, then hands off to the shared
/// customer storefront in [BusinessProfileViewMode.merchantPreview]. There is
/// deliberately no second storefront implementation.
///
/// The business id is never taken from a route or query value: it comes from
/// the owner business the backend returned for this session, so a merchant
/// cannot preview somebody else's store.
class StorePreviewPage extends StatelessWidget {
  /// Test seam mirroring the one on [BusinessProfilePage]: an already-started
  /// storefront bloc to render against. Nothing in the app supplies it, so the
  /// preview keeps building its own from the public contracts in production.
  @visibleForTesting
  final BusinessProfileBloc? storefrontBloc;

  const StorePreviewPage({super.key, this.storefrontBloc});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: BlocBuilder<BusinessBloc, BusinessState>(
        builder: (context, state) {
          if (state.business == null) {
            return _PreviewScaffold(
              child: state.status == BusinessStatus.failure
                  ? _PreviewFailure(
                      message: state.errorMessage,
                      onRetry: () => context.read<BusinessBloc>().add(
                        const BusinessStarted(),
                      ),
                    )
                  : const Center(child: CircularProgressIndicator()),
            );
          }

          return BusinessProfilePage(
            // Identity only. The storefront refuses to render anything until
            // the public detail request succeeds, so this carries no display
            // facts at all - not even owner-derived ones that happen to also be
            // public.
            business: identitySeed(state.business!),
            viewMode: BusinessProfileViewMode.merchantPreview,
            // Customer navigation is replaced by a close action in preview, so
            // this is never invoked; it stays required by the shared widget.
            onNavChanged: (_) {},
            onClosePreview: () => Navigator.of(context).maybePop(),
            bloc: storefrontBloc,
          );
        },
      ),
    );
  }

  /// Carries the trusted business id and nothing else.
  ///
  /// The owner record is used to answer "which business is mine", never "what
  /// do customers see". Every other field is left blank on purpose: the
  /// remaining values are constructor requirements, and the storefront's
  /// preview gate keeps them unrendered until public details arrive.
  ///
  /// Exposed for test so the boundary is proved at the data flow rather than by
  /// searching rendered labels.
  @visibleForTesting
  static HomeBusiness identitySeed(OwnerBusiness business) {
    return HomeBusiness(
      id: business.id,
      name: '',
      category: '',
      address: '',
      products: const [],
      rating: 0,
      colorValue: 0xffdeeef8,
    );
  }
}

class _PreviewScaffold extends StatelessWidget {
  final Widget child;

  const _PreviewScaffold({required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              height: 66,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    'merchantPreview.title'.tr(),
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
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _PreviewFailure extends StatelessWidget {
  final String? message;
  final VoidCallback onRetry;

  const _PreviewFailure({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.storefront_outlined,
              size: 44,
              color: MerzoxColors.kColor8D99AE,
            ),
            const SizedBox(height: 12),
            Text(
              message == null || message!.isEmpty
                  ? 'merchantPreview.loadError'.tr()
                  : localizeApiErrorOrRaw(message!),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MerzoxColors.kColor5E5E5E,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              child: Text('merchantPreview.retry'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
