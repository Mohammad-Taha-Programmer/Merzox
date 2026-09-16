import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:merzox/core/widgets/merzox_back_chevron.dart';
import 'package:merzox/core/localization/api_error_localizer.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/core/widgets/merzox_icons.dart';
import 'package:merzox/core/constants/money.dart';
import 'package:merzox/features/business_profile/pages/business_profile_page.dart';
import 'package:merzox/features/home/presentation/bloc/home_state_.dart';
import 'package:merzox/features/home/widgets/business_id_badge.dart';
import 'package:merzox/features/home/widgets/business_rating_stars.dart';
import 'package:merzox/features/product_details/pages/product_details_page.dart';
import 'package:merzox/features/search/bloc/search_bloc.dart';
import 'package:merzox/features/search/bloc/search_event.dart';
import 'package:merzox/features/search/bloc/search_refinement.dart';
import 'package:merzox/features/search/bloc/search_state.dart';
import 'package:merzox/services/api_service.dart';

class SearchPage extends StatefulWidget {
  /// Optional seams keep tap behavior testable without starting destination
  /// page network work. Production callers leave both values null.
  final ValueChanged<SearchBusinessApiModel>? onBusinessResultTap;
  final ValueChanged<SearchProductApiModel>? onProductResultTap;

  const SearchPage({
    super.key,
    this.onBusinessResultTap,
    this.onProductResultTap,
  });

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final TextEditingController _controller;
  late final TextEditingController _productController;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _productController = TextEditingController();
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _productController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _setQuery(String query) {
    _controller
      ..text = query
      ..selection = TextSelection.collapsed(offset: query.length);
    context.read<SearchBloc>().add(SearchQueryChanged(query));
  }

  void _openBusiness(SearchBusinessApiModel business) {
    final tapOverride = widget.onBusinessResultTap;
    if (tapOverride != null) {
      tapOverride(business);
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => Directionality(
          textDirection: Directionality.of(context),
          child: BusinessProfilePage(
            business: HomeBusiness.fromApi(business),
            onNavChanged: (index) {
              Navigator.of(routeContext).pop();
              if (context.mounted) {
                context.go('/home?tab=$index');
              }
            },
          ),
        ),
      ),
    );
  }

  void _openProduct(SearchProductApiModel item) {
    final tapOverride = widget.onProductResultTap;
    if (tapOverride != null) {
      tapOverride(item);
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Directionality(
          textDirection: Directionality.of(context),
          child: ProductDetailsPage(
            business: HomeBusiness.fromApi(item.business),
            product: item.product,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: BlocBuilder<SearchBloc, SearchState>(
            builder: (context, state) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                children: [
                  _SearchTopBar(onBack: () => Navigator.of(context).pop()),
                  const SizedBox(height: 24),
                  _SearchField(
                    controller: _controller,
                    focusNode: _focusNode,
                    onChanged: (value) {
                      context.read<SearchBloc>().add(SearchQueryChanged(value));
                    },
                    onSubmitted: (value) {
                      context.read<SearchBloc>().add(SearchSubmitted(value));
                    },
                    onClear: () => _setQuery(''),
                    hasText: state.hasQuery,
                  ),
                  // Always, not only once a shop name is typed. Gating them
                  // on that made the goods box unreachable - it is half the
                  // search, and it was sitting behind the other half.
                  const SizedBox(height: 16),
                  _SearchRefinementFields(
                    refinement: state.refinement,
                    productController: _productController,
                    onMatch: (SearchMatch match) => context
                        .read<SearchBloc>()
                        .add(SearchMatchChanged(match)),
                    onProduct: (String value) => context.read<SearchBloc>().add(
                      SearchProductChanged(value),
                    ),
                    onProductMatch: (SearchMatch match) => context
                        .read<SearchBloc>()
                        .add(SearchProductMatchChanged(match)),
                  ),
                  const SizedBox(height: 26),
                  if (!state.hasQuery)
                    _SearchHistory(
                      history: state.history,
                      onSelect: _setQuery,
                      onRemove: (query) {
                        context.read<SearchBloc>().add(
                          SearchHistoryItemRemoved(query),
                        );
                      },
                      onClear: () {
                        context.read<SearchBloc>().add(
                          const SearchHistoryCleared(),
                        );
                      },
                    )
                  else ...[
                    if (state.status == SearchStatus.loading)
                      const Center(child: CircularProgressIndicator())
                    // A search that could not be run used to look exactly like
                    // a search that found nothing: the screen had no failure
                    // state at all, so the reader was told "no results" about a
                    // question the server never answered.
                    else if (state.status == SearchStatus.failure)
                      _SearchFailed(
                        message: state.errorMessage,
                        onRetry: () => context.read<SearchBloc>().add(
                          SearchSubmitted(state.query),
                        ),
                      )
                    else if (state.hasExactBusinessMatch)
                      _ExactPublicIdResults(
                        business: state.businesses.single,
                        products: state.products,
                        onBusinessTap: _openBusiness,
                        onProductTap: _openProduct,
                      )
                    else ...[
                      _SearchTabs(selectedIndex: state.selectedTab),
                      const SizedBox(height: 26),
                      if (state.selectedTab == 0)
                        _ProductResults(
                          products: state.products,
                          onProductTap: _openProduct,
                        )
                      else
                        _BusinessResults(
                          businesses: state.businesses,
                          onBusinessTap: _openBusiness,
                        ),
                    ],
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SearchTopBar extends StatelessWidget {
  final VoidCallback onBack;

  const _SearchTopBar({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            'search.title'.tr(),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2B2B2B),
            ),
          ),
          // The artboard's chevron, which decides its own direction. This drew
          // Material's `chevron_right_rounded` behind a `isRtl ? ... : ...`,
          // and Material mirrors that icon in a right-to-left page itself - so
          // the two turns cancelled and the mark pointed away from the way
          // back. It was also the wrong mark: a rounded Material chevron where
          // every other board draws the artboard's.
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: MerzoxBackChevronButton(
              valueKey: const ValueKey<String>('search.back'),
              semanticsLabel: 'common.back'.tr(),
              onTap: onBack,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final bool hasText;

  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    required this.hasText,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textAlign: TextAlign.start,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'search.hint'.tr(),
          hintStyle: TextStyle(color: MerzoxColors.kColorC7C7C7, fontSize: 13),
          // The magnifier leads and the clear follows, which puts the glass at
          // the right of an Arabic box and at the left of an English one, and
          // the cross opposite it. They were the other way round: the cross sat
          // where the eye looks for the search.
          prefixIcon: Icon(
            MerzoxIcons.searchPageSearch,
            color: kMerzoxSearchGlassColour,
            // The size it drew at as a Material magnifier, converted.
            size: 28 * MerzoxIcons.searchSizeFactor,
          ),
          suffixIcon: hasText
              ? IconButton(
                  key: const ValueKey<String>('search.clear'),
                  tooltip: 'search.clear'.tr(),
                  onPressed: onClear,
                  icon: Icon(
                    Icons.cancel_rounded,
                    color: MerzoxColors.kColorD8D8D8,
                    size: 18,
                  ),
                )
              : null,
          filled: true,
          fillColor: MerzoxColors.kColorF9F9F9,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        ),
      ),
    );
  }
}

/// The two questions under the search box: where the words sit, and what the
/// shop has to sell.
///
/// Shown once there is something to search for, so the empty screen stays the
/// list of past searches it has always been.
class _SearchRefinementFields extends StatelessWidget {
  final SearchRefinement refinement;
  final TextEditingController productController;
  final ValueChanged<SearchMatch> onMatch;
  final ValueChanged<String> onProduct;
  final ValueChanged<SearchMatch> onProductMatch;

  const _SearchRefinementFields({
    required this.refinement,
    required this.productController,
    required this.onMatch,
    required this.onProduct,
    required this.onProductMatch,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _RefinementRow(
          key: const ValueKey<String>('search.shopMatch'),
          label: 'search.shopMatchLabel'.tr(),
          options: SearchMatch.forShops,
          selected: refinement.match,
          onChanged: onMatch,
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 44,
          child: TextField(
            key: const ValueKey<String>('search.productField'),
            controller: productController,
            onChanged: onProduct,
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'search.productHint'.tr(),
              hintStyle: TextStyle(
                color: MerzoxColors.kColorC7C7C7,
                fontSize: 13,
              ),
              // The same order as the box above it: the label and the glass
              // lead, the cross follows - so in Arabic they read right to left
              // as `يبيع`, the glass, the words, the cross.
              prefixIcon: Padding(
                padding: const EdgeInsetsDirectional.only(start: 14, end: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'search.productLabel'.tr(),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: MerzoxColors.kColor707070,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      MerzoxIcons.searchPageSearch,
                      color: kMerzoxSearchGlassColour,
                      size: 22 * MerzoxIcons.searchSizeFactor,
                    ),
                  ],
                ),
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 0,
                minHeight: 0,
              ),
              suffixIcon: refinement.hasProduct
                  ? IconButton(
                      key: const ValueKey<String>('search.clearProduct'),
                      tooltip: 'search.clear'.tr(),
                      onPressed: () {
                        productController.clear();
                        onProduct('');
                      },
                      icon: Icon(
                        Icons.cancel_rounded,
                        color: MerzoxColors.kColorD8D8D8,
                        size: 18,
                      ),
                    )
                  : null,
              suffixIconConstraints: const BoxConstraints(
                minWidth: 40,
                minHeight: 0,
              ),
              filled: true,
              fillColor: MerzoxColors.kColorF9F9F9,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(5),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // No label: it sits directly under the box it governs, and that box
        // already says `يبيع`. Saying it twice reads as two questions.
        _RefinementRow(
          key: const ValueKey<String>('search.productMatch'),
          label: '',
          options: SearchMatch.forProducts,
          selected: refinement.productMatch,
          onChanged: onProductMatch,
        ),
      ],
    );
  }
}

/// One question, as a row of answers with the current one filled in.
class _RefinementRow extends StatelessWidget {
  final String label;
  final List<SearchMatch> options;
  final SearchMatch selected;
  final ValueChanged<SearchMatch> onChanged;

  const _RefinementRow({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  static String labelFor(SearchMatch match) => switch (match) {
    SearchMatch.starts => 'search.matchStarts'.tr(),
    SearchMatch.contains => 'search.matchContains'.tr(),
    SearchMatch.ends => 'search.matchEnds'.tr(),
    SearchMatch.similar => 'search.matchSimilar'.tr(),
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 62,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: MerzoxColors.kColor707070,
            ),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final SearchMatch option in options)
                _RefinementChip(
                  label: labelFor(option),
                  isSelected: option == selected,
                  onTap: () => onChanged(option),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RefinementChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _RefinementChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? MerzoxColors.kColor3D5A80
                : MerzoxColors.kColorF9F9F9,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isSelected ? Colors.white : MerzoxColors.kColor707070,
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchHistory extends StatelessWidget {
  final List<String> history;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onRemove;
  final VoidCallback onClear;

  const _SearchHistory({
    required this.history,
    required this.onSelect,
    required this.onRemove,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    // Nothing until something has been searched for. This used to draw three
    // invented rows - a pair of shoes and a shop nobody here has heard of -
    // which could not be removed one by one or by `مسح الجميع`, because there
    // was nothing behind them to remove.
    if (history.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            TextButton(
              onPressed: onClear,
              child: Text(
                'search.clearAll'.tr(),
                style: TextStyle(
                  color: MerzoxColors.kColor3D5A80,
                  fontSize: 14,
                ),
              ),
            ),
            const Spacer(),
            Text(
              'search.previousSearches'.tr(),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: MerzoxColors.kColor3D5A80,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...history.map(
          (query) => _HistoryTile(
            query: query,
            removable: true,
            onSelect: () => onSelect(query),
            onRemove: () => onRemove(query),
          ),
        ),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final String query;
  final bool removable;
  final VoidCallback onSelect;
  final VoidCallback onRemove;

  const _HistoryTile({
    required this.query,
    required this.removable,
    required this.onSelect,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      margin: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: MerzoxColors.kColorF9F9F9,
        borderRadius: BorderRadius.circular(5),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: onSelect,
          dense: true,
          title: Text(
            query,
            textAlign: TextAlign.start,
            style: const TextStyle(fontSize: 14, color: Color(0xFF464646)),
          ),
          leading: IconButton(
            key: ValueKey<String>('search.history.remove.$query'),
            tooltip: 'common.remove'.tr(),
            onPressed: removable ? onRemove : null,
            icon: Icon(
              Icons.cancel_rounded,
              color: MerzoxColors.kColorD8D8D8,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchTabs extends StatelessWidget {
  final int selectedIndex;

  const _SearchTabs({required this.selectedIndex});

  @override
  Widget build(BuildContext context) {
    final labels = ['favorites.products'.tr(), 'nav.stores'.tr()];

    return Container(
      height: 38,
      margin: const EdgeInsets.symmetric(horizontal: 42),
      decoration: BoxDecoration(
        border: Border.all(color: MerzoxColors.kColorEE6C4D),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final active = selectedIndex == index;

          return Expanded(
            child: InkWell(
              onTap: () {
                context.read<SearchBloc>().add(SearchTabChanged(index));
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                alignment: Alignment.center,
                color: active ? MerzoxColors.kColorEE6C4D : Colors.white,
                child: Text(
                  labels[index],
                  style: TextStyle(
                    fontSize: 13,
                    color: active ? Colors.white : MerzoxColors.kColor3D5A80,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
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

class _ExactPublicIdResults extends StatelessWidget {
  final SearchBusinessApiModel business;
  final List<SearchProductApiModel> products;
  final ValueChanged<SearchBusinessApiModel> onBusinessTap;
  final ValueChanged<SearchProductApiModel> onProductTap;

  const _ExactPublicIdResults({
    required this.business,
    required this.products,
    required this.onBusinessTap,
    required this.onProductTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      key: ValueKey<String>('exact-public-id-results-${business.publicId}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'nav.stores'.tr(),
          style: const TextStyle(
            color: Color(0xFF2B2B2B),
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        _BusinessResults(
          businesses: <SearchBusinessApiModel>[business],
          onBusinessTap: onBusinessTap,
        ),
        if (products.isNotEmpty) ...<Widget>[
          const SizedBox(height: 24),
          Text(
            'favorites.products'.tr(),
            style: const TextStyle(
              color: Color(0xFF2B2B2B),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          _ProductResults(products: products, onProductTap: onProductTap),
        ],
      ],
    );
  }
}

class _ProductResults extends StatelessWidget {
  final List<SearchProductApiModel> products;
  final ValueChanged<SearchProductApiModel> onProductTap;

  const _ProductResults({required this.products, required this.onProductTap});

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const _NoResults();
    }

    final tiles = products
        .map(
          (item) =>
              _ProductResultTile(item: item, onTap: () => onProductTap(item)),
        )
        .toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Column(
            children: <Widget>[
              for (var index = 0; index < tiles.length; index++) ...<Widget>[
                tiles[index],
                if (index != tiles.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }

        final tileWidth = (constraints.maxWidth - 12) / 2;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: tiles
              .map((tile) => SizedBox(width: tileWidth, child: tile))
              .toList(growable: false),
        );
      },
    );
  }
}

class _ProductResultTile extends StatelessWidget {
  final SearchProductApiModel item;
  final VoidCallback onTap;

  const _ProductResultTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final product = item.product;
    final title = product.name.isEmpty
        ? 'search.productFallback'.tr()
        : product.name;
    final businessName = item.business.name.trim();
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return Semantics(
      button: true,
      label: title,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFE7EBF0)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey<String>('search-product-result-${product.id}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 118),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  _ResultImage(
                    imageUrl: product.imageUrl,
                    fallbackIcon: Icons.shopping_bag_outlined,
                    color: MerzoxColors.kColorF7F8FA,
                    size: 92,
                    borderRadius: 9,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.start,
                                style: const TextStyle(
                                  fontSize: 15,
                                  height: 1.3,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF2B2B2B),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              isRtl
                                  ? Icons.chevron_left_rounded
                                  : Icons.chevron_right_rounded,
                              size: 22,
                              color: MerzoxColors.kColor8D99AE,
                            ),
                          ],
                        ),
                        if (businessName.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 7),
                          Row(
                            children: <Widget>[
                              Icon(
                                Icons.storefront_outlined,
                                size: 15,
                                color: MerzoxColors.kColor707070,
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  businessName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.start,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: MerzoxColors.kColor707070,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 9),
                        Wrap(
                          spacing: 8,
                          runSpacing: 5,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: <Widget>[
                            Text(
                              '₪ ${merzoxAmount(product.displayPrice)}',
                              key: ValueKey<String>(
                                'search-product-price-${product.id}',
                              ),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: MerzoxColors.kColorEE6C4D,
                              ),
                            ),
                            if (!product.hasVariants && product.hasDiscount)
                              Text(
                                '₪ ${merzoxAmount(product.price)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: MerzoxColors.kColor8D99AE,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                            if (product.ratingCount > 0 &&
                                product.rating.isFinite)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  // One star beside a figure, so it is a
                                  // rating being read rather than one asked
                                  // for: the display star, sized like the 16
                                  // it replaces.
                                  Icon(
                                    MerzoxIcons.searchPageRatingStarFull,
                                    size: 16 * MerzoxIcons.ratingStarSizeFactor,
                                    color: const Color(0xFFFFB703),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${product.rating.toStringAsFixed(1)} '
                                    '(${product.ratingCount})',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: MerzoxColors.kColor707070,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BusinessResults extends StatelessWidget {
  final List<SearchBusinessApiModel> businesses;
  final ValueChanged<SearchBusinessApiModel> onBusinessTap;

  const _BusinessResults({
    required this.businesses,
    required this.onBusinessTap,
  });

  @override
  Widget build(BuildContext context) {
    if (businesses.isEmpty) {
      return const _NoResults();
    }

    return Column(
      children: <Widget>[
        for (var index = 0; index < businesses.length; index++) ...<Widget>[
          _BusinessResultTile(
            business: businesses[index],
            onTap: () => onBusinessTap(businesses[index]),
          ),
          if (index != businesses.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _BusinessResultTile extends StatelessWidget {
  final SearchBusinessApiModel business;
  final VoidCallback onTap;

  const _BusinessResultTile({required this.business, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final title = business.name.isEmpty
        ? 'search.businessFallback'.tr()
        : business.name;
    final displayId = business.publicId.trim().isEmpty
        ? business.id
        : business.publicId;
    final details = <String>[
      business.category.trim(),
      business.address.trim(),
    ].where((value) => value.isNotEmpty).toList(growable: false);
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final productsLabel = 'favorites.products'.tr();

    return Semantics(
      button: true,
      label: title,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFE7EBF0)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey<String>('search-business-result-${business.id}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 128),
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _ResultImage(
                    imageUrl: business.logoUrl,
                    fallbackText: title,
                    fallbackIcon: Icons.storefront_outlined,
                    color: Color(business.colorValue),
                    size: 82,
                    borderRadius: 10,
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.start,
                                style: const TextStyle(
                                  fontSize: 16,
                                  height: 1.25,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF2B2B2B),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              isRtl
                                  ? Icons.chevron_left_rounded
                                  : Icons.chevron_right_rounded,
                              size: 23,
                              color: MerzoxColors.kColor8D99AE,
                            ),
                          ],
                        ),
                        if (details.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 6),
                          Text(
                            details.join(' • '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.start,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: MerzoxColors.kColor707070,
                            ),
                          ),
                        ],
                        const SizedBox(height: 9),
                        Wrap(
                          spacing: 9,
                          runSpacing: 7,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: <Widget>[
                            BusinessIdBadge(
                              id: displayId,
                              dialogTitle: 'home.businessId.title'.tr(),
                              copyLabel: 'home.businessId.copy'.tr(),
                              copiedMessage: 'home.businessId.copied'.tr(),
                              closeLabel: 'home.businessId.close'.tr(),
                              tapHint: 'home.businessId.tapHint'.tr(),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                BusinessRatingStars(
                                  rating: business.rating,
                                  ratingCount: business.ratingCount,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '(${business.ratingCount})',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: MerzoxColors.kColor707070,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Semantics(
                            label: '$productsLabel: ${business.productCount}',
                            child: Container(
                              key: ValueKey<String>(
                                'search-business-product-count-${business.id}',
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: MerzoxColors.kColorF7F8FA,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(
                                    MerzoxIcons.searchPageProductsCount,
                                    size:
                                        14 *
                                        MerzoxIcons.productsCountSizeFactor,
                                    color: MerzoxColors.kColor3D5A80,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${business.productCount}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: MerzoxColors.kColor3D5A80,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultImage extends StatelessWidget {
  final String imageUrl;
  final IconData fallbackIcon;
  final Color color;
  final String? fallbackText;
  final double size;
  final double borderRadius;

  const _ResultImage({
    required this.imageUrl,
    required this.fallbackIcon,
    required this.color,
    this.fallbackText,
    this.size = 52,
    this.borderRadius = 4,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: imageUrl.isEmpty
            ? Container(
                color: color,
                alignment: Alignment.center,
                child: fallbackText == null
                    ? Icon(fallbackIcon, color: MerzoxColors.kColor3D5A80)
                    : Text(
                        fallbackText!.characters.take(2).toString(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: MerzoxColors.kColor3D5A80,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              )
            : Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: color,
                  child: Icon(fallbackIcon, color: MerzoxColors.kColor3D5A80),
                ),
              ),
      ),
    );
  }
}

/// A search that could not be run, said so.
///
/// Distinct from a search that found nothing, and the distinction is the whole
/// point: they were the same screen, so a network fault, a server error and an
/// empty shelf all read as "no results" - and a reader reporting "the search
/// returns nothing" could have meant any of the three.
class _SearchFailed extends StatelessWidget {
  final String? message;
  final VoidCallback onRetry;

  const _SearchFailed({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey<String>('search.failed'),
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.cloud_off_rounded,
            size: 42,
            color: MerzoxColors.kColor98C1D9,
          ),
          const SizedBox(height: 12),
          Text(
            'search.failed'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: MerzoxColors.kColor464646,
            ),
          ),
          if (message != null && message!.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              localizeApiErrorOrRaw(message!),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: MerzoxColors.kColor767676),
            ),
          ],
          const SizedBox(height: 16),
          TextButton(onPressed: onRetry, child: Text('common.retry'.tr())),
        ],
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 42,
            color: MerzoxColors.kColor98C1D9,
          ),
          const SizedBox(height: 12),
          Text(
            'search.noResults'.tr(),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: MerzoxColors.kColor464646,
            ),
          ),
        ],
      ),
    );
  }
}
