import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:merzox/core/auth/auth_gate.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_bloc.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_event.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_state.dart';
import 'package:merzox/features/home/presentation/bloc/home_state_.dart';
import 'package:merzox/features/product_details/pages/product_details_page.dart';
import 'package:merzox/services/api_service.dart';

class BusinessProfilePage extends StatelessWidget {
  final HomeBusiness business;
  final ValueChanged<int> onNavChanged;

  const BusinessProfilePage({
    super.key,
    required this.business,
    required this.onNavChanged,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          BusinessProfileBloc()..add(BusinessProfileStarted(business.id)),
      child: _BusinessProfileView(
        business: business,
        onNavChanged: onNavChanged,
      ),
    );
  }
}

class _BusinessProfileView extends StatelessWidget {
  final HomeBusiness business;
  final ValueChanged<int> onNavChanged;

  const _BusinessProfileView({
    required this.business,
    required this.onNavChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: BlocBuilder<BusinessProfileBloc, BusinessProfileState>(
          builder: (context, state) {
            final resolvedBusiness = state.business == null
                ? business
                : HomeBusiness.fromDetail(state.business!);
            return Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 124),
                  children: [
                    _TopBar(onBack: () => Navigator.of(context).pop()),
                    if (state.detailsStatus ==
                        BusinessProfileSectionStatus.loading)
                      const LinearProgressIndicator(minHeight: 2)
                    else if (state.detailsStatus ==
                        BusinessProfileSectionStatus.failure)
                      _SectionFailure(
                        message: state.detailsError,
                        onRetry: () => context.read<BusinessProfileBloc>().add(
                          const BusinessProfileDetailsRetryRequested(),
                        ),
                        compact: true,
                      ),
                    const SizedBox(height: 20),
                    _Hero(business: resolvedBusiness),
                    const SizedBox(height: 12),
                    Text(
                      resolvedBusiness.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2B2B2B),
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      'ID: ${resolvedBusiness.displayId}',
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 15),
                    _Stats(
                      followerCount: resolvedBusiness.followerCount,
                      productCount: resolvedBusiness.productCount,
                    ),
                    const SizedBox(height: 22),
                    _MainTabs(selectedIndex: state.mainTabIndex),
                    const SizedBox(height: 22),
                    if (state.mainTabIndex == 0)
                      _AboutTab(state: state, business: resolvedBusiness)
                    else if (state.mainTabIndex == 1)
                      _ProductsTab(state: state, business: resolvedBusiness)
                    else
                      _ReviewsTab(state: state),
                  ],
                ),
                PositionedDirectional(
                  end: 0,
                  bottom: 106,
                  child: _ChatButton(
                    onPressed: () => AuthGate.run(
                      context,
                      // The thread is created by the chat route on first open,
                      // so only the store id has to travel with the tap.
                      onAuthenticated: () => context.push(
                        Uri(
                          path: '/chat',
                          queryParameters: {
                            'businessId': resolvedBusiness.id,
                            'title': resolvedBusiness.name,
                          },
                        ).toString(),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: _ProfileBottomNavigationBar(
        selectedIndex: 0,
        onChanged: onNavChanged,
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback onBack;

  const _TopBar({required this.onBack});

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return SizedBox(
      height: 42,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: IconButton(
              tooltip: 'رجوع',
              onPressed: onBack,
              icon: Icon(
                isRtl
                    ? Icons.chevron_right_rounded
                    : Icons.chevron_left_rounded,
                size: 34,
              ),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  Icons.notifications_none_rounded,
                  size: 22,
                  color: MerzoxColors.kColor98C1D9,
                ),
                PositionedDirectional(
                  top: 1,
                  end: -1,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: MerzoxColors.kColorEE6C4D,
                      shape: BoxShape.circle,
                    ),
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

class _Hero extends StatelessWidget {
  final HomeBusiness business;

  const _Hero({required this.business});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 164,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                height: 96,
                color: MerzoxColors.kColorEEF6FB,
                child: CustomPaint(painter: _WavePainter()),
              ),
            ),
          ),
          if (business.category.trim().isNotEmpty)
            Positioned(
              top: 15,
              child: Container(
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 34),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: MerzoxColors.kColor3D5A80,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  business.category,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          const PositionedDirectional(
            top: 3,
            end: 7,
            child: Text('🙂', style: TextStyle(fontSize: 18)),
          ),
          Positioned(
            top: 50,
            child: Container(
              width: 112,
              height: 112,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: MerzoxColors.kColorF9F9F9,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Center(
                  child: Text(
                    business.name.trim().isEmpty
                        ? ''
                        : business.name.trim().characters.first,
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: MerzoxColors.kColor3D5A80,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  final int followerCount;
  final int productCount;

  const _Stats({required this.followerCount, required this.productCount});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Stat(
          value: '$followerCount',
          label: 'متابع',
          icon: Icons.person_add_alt_1_outlined,
        ),
        const SizedBox(width: 28),
        _Stat(
          value: '$productCount',
          label: 'منتج',
          icon: Icons.inventory_2_outlined,
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;

  const _Stat({required this.value, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 23, color: MerzoxColors.kColor98C1D9),
        const SizedBox(width: 8),
        Text('$value $label', style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}

class _MainTabs extends StatelessWidget {
  final int selectedIndex;

  const _MainTabs({required this.selectedIndex});

  @override
  Widget build(BuildContext context) {
    final labels = ['عن المتجر', 'المنتجات', 'التقييمات'];

    return Container(
      height: 46,
      decoration: BoxDecoration(
        border: Border.all(color: MerzoxColors.kColor98C1D9),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final selected = selectedIndex == index;
          return Expanded(
            child: InkWell(
              onTap: () {
                context.read<BusinessProfileBloc>().add(
                  BusinessProfileMainTabChanged(index),
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? MerzoxColors.kColor3D5A80 : Colors.white,
                  border: BorderDirectional(
                    start: index == 0
                        ? BorderSide.none
                        : BorderSide(color: MerzoxColors.kColor98C1D9),
                  ),
                ),
                child: Text(
                  labels[index],
                  style: TextStyle(
                    color: selected ? Colors.white : MerzoxColors.kColor3D5A80,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _AboutTab extends StatelessWidget {
  final BusinessProfileState state;
  final HomeBusiness business;

  const _AboutTab({required this.state, required this.business});

  @override
  Widget build(BuildContext context) {
    if (state.business == null &&
        state.detailsStatus == BusinessProfileSectionStatus.loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (state.business == null &&
        state.detailsStatus == BusinessProfileSectionStatus.failure) {
      return _SectionFailure(
        message: state.detailsError,
        onRetry: () => context.read<BusinessProfileBloc>().add(
          const BusinessProfileDetailsRetryRequested(),
        ),
      );
    }

    final services =
        state.business?.products
            .where((product) => product.isService)
            .toList() ??
        const <BusinessProductApiModel>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          business.description.trim().isEmpty
              ? 'catalog.noBusinessDescription'.tr()
              : business.description,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            height: 1.75,
            color: Color(0xFF2B2B2B),
          ),
        ),
        if (business.address.trim().isNotEmpty) ...[
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 19,
                color: MerzoxColors.kColor3D5A80,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  business.address,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: MerzoxColors.kColor767676,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 34),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Text(
            'catalog.services'.tr(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: MerzoxColors.kColor2B2B2B,
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (services.isEmpty)
          _SectionEmpty(message: 'catalog.noServices'.tr())
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.end,
            children: services
                .map(
                  (service) => SizedBox(
                    width: 92,
                    child: Column(
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: MerzoxColors.kColorEFEFEF,
                            ),
                          ),
                          child: Icon(
                            Icons.miscellaneous_services_outlined,
                            color: MerzoxColors.kColor3D5A80,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          service.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: MerzoxColors.kColor767676,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }
}

class _ProductsTab extends StatelessWidget {
  final BusinessProfileState state;
  final HomeBusiness business;

  const _ProductsTab({required this.state, required this.business});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ProductFilters(selected: state.productClassification),
        const SizedBox(height: 14),
        if (state.productsStatus == BusinessProfileSectionStatus.loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 46),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (state.productsStatus == BusinessProfileSectionStatus.failure)
          _SectionFailure(
            message: state.productsError,
            onRetry: () => context.read<BusinessProfileBloc>().add(
              const BusinessProfileProductsRetryRequested(),
            ),
          )
        else if (state.products.isEmpty)
          _SectionEmpty(message: 'catalog.noProducts'.tr())
        else
          GridView.builder(
            itemCount: state.products.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 13,
              mainAxisSpacing: 14,
              childAspectRatio: 0.66,
            ),
            itemBuilder: (context, index) {
              final product = state.products[index];
              return _ProductCard(
                business: business,
                product: product,
                liked: state.likedProductIds.contains(product.id),
              );
            },
          ),
      ],
    );
  }
}

class _ProductFilters extends StatelessWidget {
  final String selected;

  const _ProductFilters({required this.selected});

  @override
  Widget build(BuildContext context) {
    const filters = {
      'new': 'الجديدة',
      'bestSelling': 'الأكثر مبيعاً',
      'offers': 'عروض',
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: filters.entries.map((entry) {
        final active = entry.key == selected;
        return TextButton(
          onPressed: () {
            context.read<BusinessProfileBloc>().add(
              BusinessProfileProductFilterChanged(entry.key),
            );
          },
          child: Text(
            entry.value,
            style: TextStyle(
              color: active
                  ? MerzoxColors.kColor2B2B2B
                  : MerzoxColors.kColor8D99AE,
              fontWeight: active ? FontWeight.w800 : FontWeight.w500,
              fontSize: 12,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final HomeBusiness business;
  final BusinessProductApiModel product;
  final bool liked;

  const _ProductCard({
    required this.business,
    required this.product,
    required this.liked,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: MerzoxColors.kColorEFEFEF),
      ),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  ProductDetailsPage(business: business, product: product),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _ProductImage(imageUrl: product.imageUrl),
                  ),
                  PositionedDirectional(
                    top: 8,
                    end: 8,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => AuthGate.run(
                        context,
                        onAuthenticated: () => context
                            .read<BusinessProfileBloc>()
                            .add(BusinessProfileProductLikeToggled(product.id)),
                      ),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          liked
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: liked
                              ? MerzoxColors.kColor3D5A80
                              : MerzoxColors.kColor98C1D9,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Text(
                product.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Color(0xFF2B2B2B)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  _StarRating(value: product.rating, size: 12),
                  const Spacer(),
                  Text(
                    '₪ ${product.price.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 34,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProductDetailsPage(
                        business: business,
                        product: product,
                      ),
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: MerzoxColors.kColorEE6C4D,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(4),
                    ),
                  ),
                ),
                child: const Text(
                  'أضف إلى السلة',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  final String imageUrl;

  const _ProductImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isNotEmpty) {
      return Image.network(imageUrl, fit: BoxFit.cover);
    }

    return Container(
      color: const Color(0xFFF1F1F1),
      alignment: Alignment.center,
      child: Icon(
        Icons.shopping_bag_outlined,
        color: MerzoxColors.kColor3D5A80,
        size: 46,
      ),
    );
  }
}

class _ReviewsTab extends StatefulWidget {
  final BusinessProfileState state;

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
    final saving = widget.state.status == BusinessProfileStatus.savingReview;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: _InteractiveStars(
            value: _rating,
            onChanged: (value) => setState(() => _rating = value),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _commentController,
          minLines: 1,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'اكتب تقييمك هنا',
            hintStyle: TextStyle(
              fontSize: 12,
              color: MerzoxColors.kColorC7C7C7,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: MerzoxColors.kColorB9DDF3),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
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
                          context.read<BusinessProfileBloc>().add(
                            BusinessProfileReviewSubmitted(
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
            child: const Text('نشر', style: TextStyle(fontSize: 12)),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'كل التقييمات',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        if (widget.state.reviewsStatus == BusinessProfileSectionStatus.loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (widget.state.reviewsStatus ==
                BusinessProfileSectionStatus.failure &&
            widget.state.reviews.isEmpty)
          _SectionFailure(
            message: widget.state.reviewsError,
            onRetry: () => context.read<BusinessProfileBloc>().add(
              const BusinessProfileReviewsRetryRequested(),
            ),
          )
        else ...[
          if (widget.state.reviewsStatus ==
              BusinessProfileSectionStatus.failure)
            _SectionFailure(
              message: widget.state.reviewsError,
              onRetry: () => context.read<BusinessProfileBloc>().add(
                const BusinessProfileReviewsRetryRequested(),
              ),
              compact: true,
            ),
          if (widget.state.reviews.isEmpty)
            _SectionEmpty(message: 'catalog.noReviews'.tr())
          else
            ...widget.state.reviews.map(_ReviewTile.new),
        ],
      ],
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
          CircleAvatar(radius: 15, backgroundColor: MerzoxColors.kColor98C1D9),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (review.userName.trim().isNotEmpty)
                  Text(
                    review.userName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(height: 5),
                _StarRating(value: review.rating, size: 13),
                if (review.comment.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    review.comment,
                    style: const TextStyle(fontSize: 12, height: 1.5),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionFailure extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final bool compact;

  const _SectionFailure({
    required this.message,
    required this.onRetry,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final displayMessage = message.contains('.') ? message.tr() : message;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 6 : 22),
      child: Column(
        children: [
          Text(
            displayMessage.isEmpty ? 'catalog.loadError'.tr() : displayMessage,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: MerzoxColors.kColor767676),
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text('common.retry'.tr()),
          ),
        ],
      ),
    );
  }
}

class _SectionEmpty extends StatelessWidget {
  final String message;

  const _SectionEmpty({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: MerzoxColors.kColor767676),
      ),
    );
  }
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
            color: const Color(0xFFFFC400),
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
          color: const Color(0xFFFFC400),
          size: size,
        );
      }),
    );
  }
}

class _ChatButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _ChatButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: MerzoxColors.kColor3D5A80,
        foregroundColor: Colors.white,
        fixedSize: const Size(42, 42),
      ),
      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 22),
    );
  }
}

class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = MerzoxColors.kColor3D5A80.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (var line = 0; line < 12; line++) {
      final path = Path();
      final yBase = size.height * 0.56 + line * 3.6;
      path.moveTo(0, yBase);
      path.cubicTo(
        size.width * 0.26,
        yBase - 40 + line * 1.5,
        size.width * 0.48,
        yBase + 30,
        size.width * 0.72,
        yBase - 3,
      );
      path.cubicTo(
        size.width * 0.86,
        yBase - 22,
        size.width * 0.94,
        yBase + 14,
        size.width,
        yBase - 18,
      );
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ProfileBottomNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _ProfileBottomNavigationBar({
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 92,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            Positioned.fill(
              top: 22,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 22,
                      offset: const Offset(0, -7),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 0,
              child: Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 18,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              top: 22,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    Expanded(
                      child: _ProfileNavIcon(
                        icon: Icons.home_outlined,
                        selectedIcon: Icons.home_rounded,
                        selected: selectedIndex == 0,
                        onTap: () => onChanged(0),
                      ),
                    ),
                    Expanded(
                      child: _ProfileNavIcon(
                        icon: Icons.shopping_bag_outlined,
                        selectedIcon: Icons.shopping_bag_rounded,
                        selected: selectedIndex == 1,
                        onTap: () => onChanged(1),
                      ),
                    ),
                    const SizedBox(width: 92),
                    Expanded(
                      child: _ProfileNavIcon(
                        icon: Icons.chat_bubble_outline_rounded,
                        selectedIcon: Icons.chat_bubble_rounded,
                        selected: selectedIndex == 3,
                        onTap: () => onChanged(3),
                      ),
                    ),
                    Expanded(
                      child: _ProfileNavIcon(
                        icon: Icons.person_outline_rounded,
                        selectedIcon: Icons.person_rounded,
                        selected: selectedIndex == 4,
                        onTap: () => onChanged(4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 7,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => onChanged(2),
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: MerzoxColors.kColorEE6C4D,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: MerzoxColors.kColorEE6C4D.withValues(
                          alpha: 0.32,
                        ),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.storefront_outlined,
                    color: Colors.white,
                    size: 29,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileNavIcon extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final VoidCallback onTap;

  const _ProfileNavIcon({
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Center(
        child: Icon(
          selected ? selectedIcon : icon,
          color: selected
              ? MerzoxColors.kColorEE6C4D
              : MerzoxColors.kColor8D99AE,
          size: selected ? 26 : 25,
        ),
      ),
    );
  }
}
