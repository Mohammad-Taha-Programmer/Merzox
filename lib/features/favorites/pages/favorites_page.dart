import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/colors.dart';
import '../../../services/api_service.dart';
import '../../business_profile/pages/business_profile_page.dart';
import '../../home/presentation/bloc/home_state_.dart';
import '../../product_details/pages/product_details_page.dart';
import '../bloc/favorites_bloc.dart';
import '../bloc/favorites_event.dart';
import '../bloc/favorites_state.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.extentAfter < 220) {
      context.read<FavoritesBloc>().add(const FavoritesLoadMoreRequested());
    }
  }

  HomeBusiness _homeBusiness(SearchBusinessApiModel business) {
    return HomeBusiness.fromApi(business);
  }

  Future<void> _openBusiness(SearchBusinessApiModel business) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BusinessProfilePage(
          business: _homeBusiness(business),
          onNavChanged: (index) {
            Navigator.of(context).pop();
            context.go('/home?tab=$index');
          },
        ),
      ),
    );
  }

  Future<void> _openProduct(FavoriteProductApiModel favorite) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductDetailsPage(
          business: _homeBusiness(favorite.business),
          product: favorite.product,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<FavoritesBloc, FavoritesState>(
      listenWhen: (previous, current) =>
          previous.messageCode != current.messageCode ||
          previous.errorMessage != current.errorMessage,
      listener: (context, state) {
        final message = state.messageCode.isNotEmpty
            ? state.messageCode.tr()
            : state.errorMessage;
        if (message.isEmpty) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      },
      builder: (context, state) {
        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: Column(
              children: [
                const _FavoritesHeader(),
                _FavoritesTabs(selectedTab: state.selectedTab),
                Expanded(child: _buildContent(state)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent(FavoritesState state) {
    final currentIsEmpty = state.selectedTab == FavoritesTab.businesses
        ? state.businesses.isEmpty
        : state.products.isEmpty;

    if (state.status == FavoritesStatus.loading && currentIsEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: MerzoxColors.kColorEE6C4D),
      );
    }

    if (state.status == FavoritesStatus.failure && currentIsEmpty) {
      return _FavoritesFailureState(
        onRetry: () => context.read<FavoritesBloc>().add(
          const FavoritesRefreshRequested(),
        ),
      );
    }

    if (currentIsEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
            _EmptyFavoritesState(tab: state.selectedTab),
          ],
        ),
      );
    }

    final isBusinesses = state.selectedTab == FavoritesTab.businesses;
    final itemCount = isBusinesses
        ? state.businesses.length
        : state.products.length;

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _refresh,
          child: GridView.builder(
            key: ValueKey(state.selectedTab),
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 14,
              childAspectRatio: isBusinesses ? 0.93 : 0.66,
            ),
            itemCount: itemCount,
            itemBuilder: (context, index) {
              if (isBusinesses) {
                final business = state.businesses[index];
                return _FavoriteBusinessCard(
                  business: business,
                  onOpen: () => _openBusiness(business),
                  onRemove: () => context.read<FavoritesBloc>().add(
                    FavoriteBusinessRemoved(business.id),
                  ),
                );
              }

              final favorite = state.products[index];
              return _FavoriteProductCard(
                favorite: favorite,
                onOpen: () => _openProduct(favorite),
                onRemove: () => context.read<FavoritesBloc>().add(
                  FavoriteProductRemoved(
                    businessId: favorite.business.id,
                    productId: favorite.product.id,
                  ),
                ),
                onAddToCart: () => context.read<FavoritesBloc>().add(
                  FavoriteProductAddedToCart(
                    businessId: favorite.business.id,
                    productId: favorite.product.id,
                  ),
                ),
              );
            },
          ),
        ),
        if (state.status == FavoritesStatus.loadingMore)
          const PositionedDirectional(
            start: 0,
            end: 0,
            bottom: 10,
            child: Center(
              child: CircularProgressIndicator(
                color: MerzoxColors.kColorEE6C4D,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _refresh() async {
    context.read<FavoritesBloc>().add(const FavoritesRefreshRequested());
  }
}

class _FavoritesHeader extends StatelessWidget {
  const _FavoritesHeader();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 82,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            'favorites.title'.tr(),
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

class _FavoritesTabs extends StatelessWidget {
  final FavoritesTab selectedTab;

  const _FavoritesTabs({required this.selectedTab});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: MerzoxColors.kColorEE6C4D),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          _FavoriteTabButton(
            tab: FavoritesTab.products,
            label: 'favorites.products'.tr(),
            selected: selectedTab == FavoritesTab.products,
          ),
          _FavoriteTabButton(
            tab: FavoritesTab.businesses,
            label: 'favorites.businesses'.tr(),
            selected: selectedTab == FavoritesTab.businesses,
          ),
        ],
      ),
    );
  }
}

class _FavoriteTabButton extends StatelessWidget {
  final FavoritesTab tab;
  final String label;
  final bool selected;

  const _FavoriteTabButton({
    required this.tab,
    required this.label,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: selected ? MerzoxColors.kColorEE6C4D : Colors.white,
        child: InkWell(
          onTap: () =>
              context.read<FavoritesBloc>().add(FavoritesTabChanged(tab)),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : MerzoxColors.kColor3B3B3B,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FavoriteBusinessCard extends StatelessWidget {
  final SearchBusinessApiModel business;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  const _FavoriteBusinessCard({
    required this.business,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: const BorderSide(color: MerzoxColors.kColorEFEFEF),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onOpen,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Color(business.colorValue),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: business.name.toLowerCase().contains('yasmeen')
                          ? Text(
                              'Yasmeen',
                              style: TextStyle(
                                fontFamily: 'Minion',
                                color: MerzoxColors.kColor3D5A80,
                                fontSize: 22,
                              ),
                            )
                          : const Icon(
                              Icons.storefront_outlined,
                              color: MerzoxColors.kColor3D5A80,
                              size: 40,
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    business.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: MerzoxColors.kColor2B2B2B,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        height: 18,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        alignment: Alignment.center,
                        color: MerzoxColors.kColorF4F8FB,
                        child: Text(
                          'ID: ${business.publicId}',
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                            color: MerzoxColors.kColor707070,
                            fontSize: 8,
                          ),
                        ),
                      ),
                      const Spacer(),
                      _StarRating(value: business.rating, size: 11),
                    ],
                  ),
                ],
              ),
            ),
            PositionedDirectional(
              end: 0,
              bottom: 0,
              child: Tooltip(
                message: 'favorites.removeBusiness'.tr(),
                child: InkWell(
                  onTap: onRemove,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    topRight: Radius.circular(14),
                  ),
                  child: Container(
                    width: 34,
                    height: 25,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: MerzoxColors.kColor98C1D9,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(14),
                      ),
                    ),
                    child: const Text('🥰', style: TextStyle(fontSize: 14)),
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

class _FavoriteProductCard extends StatelessWidget {
  final FavoriteProductApiModel favorite;
  final VoidCallback onOpen;
  final VoidCallback onRemove;
  final VoidCallback onAddToCart;

  const _FavoriteProductCard({
    required this.favorite,
    required this.onOpen,
    required this.onRemove,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    final product = favorite.product;

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: const BorderSide(color: MerzoxColors.kColorEFEFEF),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _FavoriteProductImage(imageUrl: product.imageUrl),
                  ),
                  PositionedDirectional(
                    top: 8,
                    end: 8,
                    child: Tooltip(
                      message: 'favorites.removeProduct'.tr(),
                      child: InkWell(
                        onTap: onRemove,
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: 27,
                          height: 27,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.favorite_rounded,
                            color: MerzoxColors.kColor3D5A80,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 5),
              child: Text(
                product.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: MerzoxColors.kColor2B2B2B,
                  fontSize: 11,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  _StarRating(value: product.rating, size: 11),
                  const Spacer(),
                  if (product.hasDiscount) ...[
                    Text(
                      '₪ ${product.price.toStringAsFixed(0)}',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        color: MerzoxColors.kColor8D99AE,
                        fontSize: 10,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    '₪ ${product.displayPrice.toStringAsFixed(0)}',
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      color: MerzoxColors.kColor3B3B3B,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 9),
            SizedBox(
              height: 36,
              child: FilledButton(
                onPressed: onAddToCart,
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  backgroundColor: MerzoxColors.kColorEE6C4D,
                  foregroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(4),
                    ),
                  ),
                ),
                child: Text(
                  'favorites.addToCart'.tr(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
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

class _FavoriteProductImage extends StatelessWidget {
  final String imageUrl;

  const _FavoriteProductImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: MerzoxColors.kColorF4F8FB,
      alignment: Alignment.center,
      child: const Icon(
        Icons.inventory_2_outlined,
        color: MerzoxColors.kColor3D5A80,
        size: 38,
      ),
    );

    if (imageUrl.startsWith('assets/')) {
      return Image.asset(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      );
    }
    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      );
    }
    return fallback;
  }
}

class _StarRating extends StatelessWidget {
  final double value;
  final double size;

  const _StarRating({required this.value, required this.size});

  @override
  Widget build(BuildContext context) {
    final rounded = value.round().clamp(0, 5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        return Icon(
          index < rounded ? Icons.star_rounded : Icons.star_border_rounded,
          size: size,
          color: index < rounded
              ? MerzoxColors.kColorF2CB06
              : MerzoxColors.kColorC7C7C7,
        );
      }),
    );
  }
}

class _EmptyFavoritesState extends StatelessWidget {
  final FavoritesTab tab;

  const _EmptyFavoritesState({required this.tab});

  @override
  Widget build(BuildContext context) {
    final isBusinesses = tab == FavoritesTab.businesses;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const Icon(
            Icons.favorite_border_rounded,
            size: 96,
            color: MerzoxColors.kColor3D5A80,
          ),
          const SizedBox(height: 24),
          Text(
            isBusinesses
                ? 'favorites.emptyBusinesses'.tr()
                : 'favorites.emptyProducts'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MerzoxColors.kColor2B2B2B,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'favorites.emptyHint'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MerzoxColors.kColor707070,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoritesFailureState extends StatelessWidget {
  final VoidCallback onRetry;

  const _FavoritesFailureState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.heart_broken_outlined,
              size: 76,
              color: MerzoxColors.kColor3D5A80,
            ),
            const SizedBox(height: 20),
            Text(
              'favorites.loadError'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 18),
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
