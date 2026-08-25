import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:merzox/core/auth/auth_gate.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/features/home/presentation/bloc/home_state_.dart';
import 'package:merzox/features/product_details/bloc/product_details_bloc.dart';
import 'package:merzox/features/product_details/bloc/product_details_event.dart';
import 'package:merzox/features/product_details/bloc/product_details_state.dart';
import 'package:merzox/features/reviews/widgets/review_eligibility_notice.dart';
import 'package:merzox/services/review_eligibility_service.dart';
import 'package:merzox/services/api_service.dart';

class ProductDetailsPage extends StatelessWidget {
  final HomeBusiness business;
  final BusinessProductApiModel product;

  /// Test seam, matching the one on the storefront page: an already-started
  /// bloc to render against. Nothing in the app supplies it.
  @visibleForTesting
  final ProductDetailsBloc? bloc;

  const ProductDetailsPage({
    super.key,
    required this.business,
    required this.product,
    this.bloc,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      // An injected bloc has already been started by whoever built it;
      // re-dispatching would repeat every public request.
      create: (_) =>
          bloc ??
          (ProductDetailsBloc()..add(
            ProductDetailsStarted(
              businessId: business.id,
              initialProduct: product,
            ),
          )),
      child: _ProductDetailsView(business: business),
    );
  }
}

class _ProductDetailsView extends StatelessWidget {
  final HomeBusiness business;

  const _ProductDetailsView({required this.business});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ProductDetailsBloc, ProductDetailsState>(
      listenWhen: (previous, current) =>
          previous.message != current.message ||
          previous.errorMessage != current.errorMessage,
      listener: (context, state) {
        final text = state.errorMessage ?? state.message;
        if (text == null || text.isEmpty) return;
        final localizedText = text.contains('.') ? text.tr() : text;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(localizedText)));
      },
      builder: (context, state) {
        final product = state.product;

        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            top: false,
            child: product == null
                ? const Center(child: CircularProgressIndicator())
                : Stack(
                    children: [
                      ListView(
                        padding: const EdgeInsets.only(bottom: 96),
                        children: [
                          _ImageSlider(product: product, state: state),
                          if (state.detailsStatus ==
                              ProductDetailsSectionStatus.failure)
                            _ProductLoadFailure(
                              message: state.detailsError,
                              onRetry: () => context
                                  .read<ProductDetailsBloc>()
                                  .add(const ProductDetailsReloadRequested()),
                            ),
                          _ProductHeader(
                            product: product,
                            selectedVariant: state.selectedVariant,
                          ),
                          _Tabs(selectedIndex: state.selectedTabIndex),
                          if (state.selectedTabIndex == 0)
                            _DescriptionTab(
                              business: business,
                              product: product,
                              state: state,
                            )
                          else
                            _ReviewsTab(state: state),
                        ],
                      ),
                      PositionedDirectional(
                        end: 18,
                        top: MediaQuery.paddingOf(context).top + 58,
                        child: Builder(
                          builder: (shareContext) => _IconCircle(
                            icon: Icons.share_outlined,
                            onPressed:
                                state.status == ProductDetailsStatus.sharing ||
                                    state.status ==
                                        ProductDetailsStatus.savingReview
                                ? null
                                : () {
                                    context.read<ProductDetailsBloc>().add(
                                      ProductDetailsShareRequested(
                                        businessName: business.name,
                                        languageCode: Localizations.localeOf(
                                          context,
                                        ).languageCode,
                                        sharePositionOrigin: _shareOriginFor(
                                          shareContext,
                                        ),
                                      ),
                                    );
                                  },
                            filled: false,
                          ),
                        ),
                      ),
                      PositionedDirectional(
                        start: 18,
                        top: MediaQuery.paddingOf(context).top + 58,
                        child: _IconCircle(
                          icon: Icons.chevron_right_rounded,
                          onPressed: () => Navigator.of(context).pop(),
                          filled: false,
                        ),
                      ),
                    ],
                  ),
          ),
          bottomNavigationBar: product == null
              ? null
              : SafeArea(
                  top: false,
                  child: _BottomActions(
                    selectionRequired: state.variantSelectionRequired,
                    inStock: state.selectedSellableInStock,
                    onAdd: () => AuthGate.run(
                      context,
                      onAuthenticated: () => context
                          .read<ProductDetailsBloc>()
                          .add(const ProductDetailsAddToCartPressed()),
                    ),
                    onBuy: () => AuthGate.run(
                      context,
                      onAuthenticated: () => context
                          .read<ProductDetailsBloc>()
                          .add(const ProductDetailsBuyNowPressed()),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _ImageSlider extends StatefulWidget {
  final BusinessProductApiModel product;
  final ProductDetailsState state;

  const _ImageSlider({required this.product, required this.state});

  @override
  State<_ImageSlider> createState() => _ImageSliderState();
}

class _ImageSliderState extends State<_ImageSlider> {
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = _gallery(widget.product);

    return Column(
      children: [
        SizedBox(
          height: 302,
          child: PageView.builder(
            controller: _controller,
            reverse: Directionality.of(context) == TextDirection.rtl,
            itemCount: images.length,
            onPageChanged: (index) {
              context.read<ProductDetailsBloc>().add(
                ProductDetailsImageChanged(index),
              );
            },
            itemBuilder: (context, index) {
              final imageUrl = images[index];
              return ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(6),
                ),
                child: imageUrl.isEmpty
                    ? const _ProductPhotoPlaceholder()
                    : Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const _ProductPhotoPlaceholder(),
                      ),
              );
            },
          ),
        ),
        const SizedBox(height: 7),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(images.length, (index) {
            final active = index == widget.state.selectedImageIndex;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: active
                    ? MerzoxColors.kColor3D5A80
                    : MerzoxColors.kColor98C1D9,
                borderRadius: BorderRadius.circular(99),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _ProductHeader extends StatelessWidget {
  final BusinessProductApiModel product;
  final BusinessProductVariantApiModel? selectedVariant;

  const _ProductHeader({required this.product, required this.selectedVariant});

  @override
  Widget build(BuildContext context) {
    final selected = selectedVariant;

    final String priceText;

    if (product.hasVariants && product.variants.isEmpty) {
      priceText = 'catalog.priceUnavailable'.tr();
    } else if (selected != null) {
      priceText = '₪ ${selected.finalPrice.toStringAsFixed(0)}';
    } else if (product.hasVariants && product.hasPriceRange) {
      priceText =
          '₪ ${product.minFinalPrice!.toStringAsFixed(0)}'
          ' – '
          '₪ ${product.maxFinalPrice!.toStringAsFixed(0)}';
    } else {
      priceText = '₪ ${product.displayPrice.toStringAsFixed(0)}';
    }

    final double? listPrice;

    if (selected != null && selected.hasDiscount) {
      listPrice = selected.price;
    } else if (!product.hasVariants && product.hasDiscount) {
      listPrice = product.price;
    } else {
      listPrice = null;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      child: Row(
        children: [
          Flexible(
            flex: 2,
            child: Text(
              product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.start,
              style: const TextStyle(fontSize: 20, color: Color(0xFF2B2B2B)),
            ),
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                priceText,
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (listPrice != null)
                Text(
                  '₪ ${listPrice.toStringAsFixed(0)}',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: 13,
                    color: MerzoxColors.kColor8D99AE,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  final int selectedIndex;

  const _Tabs({required this.selectedIndex});

  @override
  Widget build(BuildContext context) {
    final labels = [
      'productDetails.tabs.description'.tr(),
      'reviews.title'.tr(),
    ];

    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: MerzoxColors.kColorEFEFEF),
          bottom: BorderSide(color: MerzoxColors.kColorEFEFEF),
        ),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final active = index == selectedIndex;
          return Expanded(
            child: InkWell(
              onTap: () {
                context.read<ProductDetailsBloc>().add(
                  ProductDetailsTabChanged(index),
                );
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: Center(
                      child: Text(
                        labels[index],
                        style: TextStyle(
                          color: active
                              ? MerzoxColors.kColor2B2B2B
                              : MerzoxColors.kColorC7C7C7,
                          fontSize: 14,
                          fontWeight: active
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: active ? 1 : 0),
                    duration: const Duration(milliseconds: 160),
                    builder: (context, widthFactor, child) {
                      return FractionallySizedBox(
                        widthFactor: widthFactor,
                        child: child,
                      );
                    },
                    child: Container(
                      height: 1,
                      color: MerzoxColors.kColorB9DDF3,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _DescriptionTab extends StatelessWidget {
  final HomeBusiness business;
  final BusinessProductApiModel product;
  final ProductDetailsState state;

  const _DescriptionTab({
    required this.business,
    required this.product,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            product.description.isEmpty
                ? 'catalog.noProductDescription'.tr()
                : product.description,
            textAlign: TextAlign.start,
            style: TextStyle(
              color: MerzoxColors.kColor666666,
              fontSize: 15,
              height: 1.85,
            ),
          ),
          const SizedBox(height: 24),
          if (product.hasVariants) ...[
            _VariantSelector(
              product: product,
              selectedVariantId: state.selectedVariantId,
            ),
            const SizedBox(height: 24),
          ],
          _QuantityRow(quantity: state.quantity),
          const SizedBox(height: 28),
          _SellerDetails(business: business),
        ],
      ),
    );
  }
}

class _VariantSelector extends StatelessWidget {
  final BusinessProductApiModel product;
  final String? selectedVariantId;

  const _VariantSelector({
    required this.product,
    required this.selectedVariantId,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'catalog.selectVariantPrompt'.tr(),
          textAlign: TextAlign.start,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        if (product.variants.isEmpty)
          Text(
            'catalog.noVariantsAvailable'.tr(),
            textAlign: TextAlign.start,
            style: TextStyle(color: MerzoxColors.kColor767676, fontSize: 13),
          )
        else
          Wrap(
            alignment: WrapAlignment.start,
            spacing: 8,
            runSpacing: 8,
            children: product.variants.map((variant) {
              final selected = selectedVariantId == variant.id;

              return ChoiceChip(
                label: Text(
                  variant.inStock
                      ? variant.label
                      : '${variant.label} — ${'catalog.outOfStock'.tr()}',
                ),
                selected: selected,
                onSelected: variant.inStock
                    ? (value) {
                        if (!value) return;

                        context.read<ProductDetailsBloc>().add(
                          ProductDetailsVariantSelected(variant.id),
                        );
                      }
                    : null,
                selectedColor: MerzoxColors.kColor98C1D9,
                side: BorderSide(
                  color: selected
                      ? MerzoxColors.kColor3D5A80
                      : MerzoxColors.kColorC7C7C7,
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}

class _QuantityRow extends StatelessWidget {
  final int quantity;

  const _QuantityRow({required this.quantity});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'merchantProduct.quantity'.tr(),
          style: const TextStyle(fontSize: 15),
        ),
        const Spacer(),
        Row(
          mainAxisSize: MainAxisSize.min,
          textDirection: TextDirection.ltr,
          children: [
            _StepperButton(
              icon: Icons.remove_rounded,
              onPressed: () => context.read<ProductDetailsBloc>().add(
                const ProductDetailsQuantityDecremented(),
              ),
            ),
            Container(
              width: 58,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.symmetric(
                  horizontal: BorderSide(color: MerzoxColors.kColor3D5A80),
                ),
              ),
              child: Text(
                '$quantity',
                style: TextStyle(
                  color: MerzoxColors.kColor666666,
                  fontSize: 15,
                ),
              ),
            ),
            _StepperButton(
              icon: Icons.add_rounded,
              onPressed: () => context.read<ProductDetailsBloc>().add(
                const ProductDetailsQuantityIncremented(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _StepperButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 32,
      child: IconButton.filled(
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: MerzoxColors.kColor3D5A80,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
        icon: Icon(icon, size: 20),
      ),
    );
  }
}

class _SellerDetails extends StatelessWidget {
  final HomeBusiness business;

  const _SellerDetails({required this.business});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'productDetails.sellerDetails'.tr(),
          style: const TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 13),
        Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: MerzoxColors.kColorEEF6FB,
              child: Text(
                business.name.isEmpty ? 'M' : business.name.characters.first,
                style: TextStyle(
                  color: MerzoxColors.kColor3D5A80,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(business.name, style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  business.address.trim().isEmpty
                      ? 'catalog.addressUnavailable'.tr()
                      : business.address,
                  style: TextStyle(
                    fontSize: 11,
                    color: MerzoxColors.kColor767676,
                  ),
                ),
              ],
            ),
            const Spacer(),
            _IconSquare(
              icon: Icons.chat_bubble_outline_rounded,
              onPressed: () => AuthGate.run(
                context,
                // The chat route opens an existing thread with this store or
                // creates one, so only the store identity travels with the tap.
                onAuthenticated: () => context.push(
                  Uri(
                    path: '/chat',
                    queryParameters: {
                      'businessId': business.id,
                      'title': business.name,
                    },
                  ).toString(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ReviewsTab extends StatefulWidget {
  final ProductDetailsState state;

  const _ReviewsTab({required this.state});

  @override
  State<_ReviewsTab> createState() => _ReviewsTabState();
}

class _ReviewsTabState extends State<_ReviewsTab> {
  final _commentController = TextEditingController();
  int _rating = 5;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final saving = widget.state.status == ProductDetailsStatus.savingReview;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.state.reviewEligibilityStatus ==
              ReviewEligibilityStatus.eligible) ...[
            Center(
              child: _InteractiveStars(
                value: _rating,
                onChanged: (value) => setState(() => _rating = value),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _commentController,
              minLines: 4,
              maxLines: 4,
              textAlign: TextAlign.start,
              decoration: InputDecoration(
                hintText: 'productDetails.reviewHint'.tr(),
                hintStyle: TextStyle(
                  color: MerzoxColors.kColorC7C7C7,
                  fontSize: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(5),
                  borderSide: BorderSide(color: MerzoxColors.kColorB9DDF3),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(5),
                  borderSide: BorderSide(color: MerzoxColors.kColorB9DDF3),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        final submitted = await AuthGate.run(
                          context,
                          onAuthenticated: () =>
                              context.read<ProductDetailsBloc>().add(
                                ProductDetailsReviewSubmitted(
                                  rating: _rating,
                                  comment: _commentController.text,
                                ),
                              ),
                        );
                        if (submitted) {
                          _commentController.clear();
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: MerzoxColors.kColorEE6C4D,
                  fixedSize: const Size(58, 32),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                child: Text(
                  'reviews.publish'.tr(),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
          if (widget.state.reviewEligibilityStatus !=
              ReviewEligibilityStatus.eligible)
            ReviewEligibilityNotice(
              status: widget.state.reviewEligibilityStatus,
              productTarget: true,
              onLogin: () async {
                await context.push<void>('/login');
                if (context.mounted) {
                  context.read<ProductDetailsBloc>().add(
                    const ProductDetailsReviewEligibilityRetryRequested(),
                  );
                }
              },
              onRetry: () => context.read<ProductDetailsBloc>().add(
                const ProductDetailsReviewEligibilityRetryRequested(),
              ),
            ),
          const SizedBox(height: 22),
          Row(
            children: [
              Text(
                'reviews.count'.tr(
                  args: [widget.state.reviews.length.toString()],
                ),
                style: TextStyle(
                  color: MerzoxColors.kColor9F9F9F,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Text(
                'reviews.allReviews'.tr(),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (widget.state.reviewsStatus == ProductDetailsSectionStatus.loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (widget.state.reviewsStatus ==
                  ProductDetailsSectionStatus.failure &&
              widget.state.reviews.isEmpty)
            _ProductLoadFailure(
              message: widget.state.reviewsError,
              onRetry: () => context.read<ProductDetailsBloc>().add(
                const ProductDetailsReviewsRetryRequested(),
              ),
            )
          else ...[
            if (widget.state.reviewsStatus ==
                ProductDetailsSectionStatus.failure)
              _ProductLoadFailure(
                message: widget.state.reviewsError,
                onRetry: () => context.read<ProductDetailsBloc>().add(
                  const ProductDetailsReviewsRetryRequested(),
                ),
              ),
            if (widget.state.reviews.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Text(
                  'catalog.noReviews'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: MerzoxColors.kColor767676),
                ),
              )
            else
              ...widget.state.reviews.map(_ReviewTile.new),
          ],
        ],
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final BusinessReviewApiModel review;

  const _ReviewTile(this.review);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: MerzoxColors.kColor98C1D9,
              ),
              const SizedBox(height: 5),
              if (review.userName.trim().isNotEmpty)
                Text(review.userName, style: const TextStyle(fontSize: 12)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    _StarRating(value: review.rating, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      '(${review.rating.toStringAsFixed(1)})',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        color: MerzoxColors.kColor9F9F9F,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  review.comment,
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    color: MerzoxColors.kColor5E5E5E,
                    fontSize: 12,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductLoadFailure extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ProductLoadFailure({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final displayMessage = message.contains('.') ? message.tr() : message;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              displayMessage.isEmpty
                  ? 'catalog.loadError'.tr()
                  : displayMessage,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: MerzoxColors.kColor767676),
            ),
          ),
          IconButton(
            tooltip: 'common.retry'.tr(),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  final VoidCallback onAdd;
  final VoidCallback onBuy;
  final bool inStock;
  final bool selectionRequired;

  const _BottomActions({
    required this.onAdd,
    required this.onBuy,
    required this.inStock,
    required this.selectionRequired,
  });

  @override
  Widget build(BuildContext context) {
    if (selectionRequired) {
      return _BottomStatusMessage(message: 'catalog.selectVariant'.tr());
    }

    if (!inStock) {
      return _BottomStatusMessage(message: 'catalog.outOfStock'.tr());
    }

    return Container(
      height: 70,
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 14),
      decoration: _bottomActionDecoration(),
      child: Row(
        children: [
          Expanded(
            child: FilledButton(
              onPressed: onAdd,
              style: FilledButton.styleFrom(
                backgroundColor: MerzoxColors.kColorEE6C4D,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadiusDirectional.horizontal(
                    start: Radius.circular(4),
                  ),
                ),
              ),
              child: Text(
                'favorites.addToCart'.tr(),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          Expanded(
            child: OutlinedButton(
              onPressed: onBuy,
              style: OutlinedButton.styleFrom(
                foregroundColor: MerzoxColors.kColor2B2B2B,
                side: BorderSide(color: MerzoxColors.kColorEE6C4D),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadiusDirectional.horizontal(
                    end: Radius.circular(4),
                  ),
                ),
              ),
              child: Text(
                'productDetails.buyNow'.tr(),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomStatusMessage extends StatelessWidget {
  final String message;

  const _BottomStatusMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      alignment: Alignment.center,
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 14),
      decoration: _bottomActionDecoration(),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: MerzoxColors.kColor767676,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

BoxDecoration _bottomActionDecoration() {
  return BoxDecoration(
    color: Colors.white,
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.05),
        blurRadius: 16,
        offset: const Offset(0, -6),
      ),
    ],
  );
}

class _InteractiveStars extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _InteractiveStars({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final rating = index + 1;
        return IconButton(
          onPressed: () => onChanged(rating),
          icon: Icon(
            rating <= value ? Icons.star_rounded : Icons.star_border_rounded,
            color: MerzoxColors.kColorF2CB06,
            size: 29,
          ),
        );
      }),
    );
  }
}

class _StarRating extends StatelessWidget {
  final double value;
  final double size;

  const _StarRating({required this.value, required this.size});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        return Icon(
          index < value.round()
              ? Icons.star_rounded
              : Icons.star_border_rounded,
          color: MerzoxColors.kColorF2CB06,
          size: size,
        );
      }),
    );
  }
}

Rect? _shareOriginFor(BuildContext context) {
  final renderObject = context.findRenderObject();

  if (renderObject is! RenderBox || !renderObject.hasSize) {
    return null;
  }

  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

class _IconCircle extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final bool filled;

  const _IconCircle({
    required this.icon,
    required this.onPressed,
    required this.filled,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: filled
            ? MerzoxColors.kColor3D5A80
            : Colors.transparent,
        foregroundColor: filled ? Colors.white : MerzoxColors.kColor3B3B3B,
      ),
      icon: Icon(icon, size: 25),
    );
  }
}

class _IconSquare extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _IconSquare({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 50,
      height: 50,
      child: IconButton.filled(
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: MerzoxColors.kColor3D5A80,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        ),
        icon: Icon(icon),
      ),
    );
  }
}

class _ProductPhotoPlaceholder extends StatelessWidget {
  const _ProductPhotoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEFEFEF),
      alignment: Alignment.center,
      child: SizedBox(
        width: 178,
        height: 230,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Positioned(
              bottom: 0,
              child: Container(
                width: 84,
                height: 162,
                decoration: BoxDecoration(
                  color: const Color(0xFFE9C3A8),
                  border: Border.all(color: const Color(0xFFB88E73)),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            Positioned(
              top: 18,
              child: Container(
                width: 58,
                height: 76,
                decoration: BoxDecoration(
                  color: MerzoxColors.kColor2B2B2B,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            Positioned(
              bottom: 52,
              child: Text(
                'Merzox',
                style: TextStyle(
                  color: MerzoxColors.kColor3D5A80,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

List<String> _gallery(BusinessProductApiModel product) {
  if (product.imageUrls.isNotEmpty) {
    return product.imageUrls;
  }

  if (product.imageUrl.isNotEmpty) {
    return [product.imageUrl];
  }

  return const ['', '', ''];
}
