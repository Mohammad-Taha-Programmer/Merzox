import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/features/search/bloc/search_bloc.dart';
import 'package:merzox/features/search/bloc/search_event.dart';
import 'package:merzox/features/search/bloc/search_state.dart';
import 'package:merzox/services/api_service.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _setQuery(String query) {
    _controller
      ..text = query
      ..selection = TextSelection.collapsed(offset: query.length);
    context.read<SearchBloc>().add(SearchQueryChanged(query));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
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
                    _SearchTabs(selectedIndex: state.selectedTab),
                    const SizedBox(height: 26),
                    if (state.status == SearchStatus.loading)
                      const Center(child: CircularProgressIndicator())
                    else if (state.selectedTab == 0)
                      _ProductResults(products: state.products)
                    else
                      _BusinessResults(businesses: state.businesses),
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
          const Text(
            'البحث',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2B2B2B),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: IconButton(
              tooltip: 'رجوع',
              onPressed: onBack,
              icon: const Icon(Icons.chevron_right_rounded, size: 34),
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
        textAlign: TextAlign.right,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'أي متجر أو منتج تريد البحث عنه',
          hintStyle: TextStyle(color: MerzoxColors.kColorC7C7C7, fontSize: 13),
          prefixIcon: hasText
              ? IconButton(
                  tooltip: 'مسح',
                  onPressed: onClear,
                  icon: Icon(
                    Icons.cancel_rounded,
                    color: MerzoxColors.kColorD8D8D8,
                    size: 18,
                  ),
                )
              : null,
          suffixIcon: Icon(
            Icons.search_rounded,
            color: MerzoxColors.kColor707070,
            size: 28,
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
    final items = history.isEmpty
        ? const ['حذاء حريمي', 'متجر جوميا', 'بوت حريمي']
        : history;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            TextButton(
              onPressed: history.isEmpty ? null : onClear,
              child: Text(
                'مسح الجميع',
                style: TextStyle(
                  color: MerzoxColors.kColor3D5A80,
                  fontSize: 14,
                ),
              ),
            ),
            const Spacer(),
            const Text(
              'تم البحث عنه سابقاً',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...items.map(
          (query) => _HistoryTile(
            query: query,
            removable: history.isNotEmpty,
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
      decoration: BoxDecoration(
        color: MerzoxColors.kColorF9F9F9,
        borderRadius: BorderRadius.circular(5),
      ),
      child: ListTile(
        onTap: onSelect,
        dense: true,
        title: Text(
          query,
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 14, color: Color(0xFF464646)),
        ),
        leading: IconButton(
          tooltip: 'إزالة',
          onPressed: removable ? onRemove : null,
          icon: Icon(
            Icons.cancel_rounded,
            color: MerzoxColors.kColorD8D8D8,
            size: 18,
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
    const labels = ['المنتجات', 'المتاجر'];

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

class _ProductResults extends StatelessWidget {
  final List<SearchProductApiModel> products;

  const _ProductResults({required this.products});

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const _NoResults();
    }

    return GridView.builder(
      itemCount: products.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.8,
        crossAxisSpacing: 22,
        mainAxisSpacing: 22,
      ),
      itemBuilder: (context, index) {
        return _ProductResultTile(item: products[index]);
      },
    );
  }
}

class _ProductResultTile extends StatelessWidget {
  final SearchProductApiModel item;

  const _ProductResultTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.product.imageUrl;

    return Row(
      textDirection: TextDirection.rtl,
      children: [
        _ResultImage(
          imageUrl: imageUrl,
          fallbackIcon: Icons.shopping_bag_outlined,
          color: MerzoxColors.kColorF7F8FA,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            item.product.name.isEmpty ? 'منتج' : item.product.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13, color: Color(0xFF2B2B2B)),
          ),
        ),
      ],
    );
  }
}

class _BusinessResults extends StatelessWidget {
  final List<SearchBusinessApiModel> businesses;

  const _BusinessResults({required this.businesses});

  @override
  Widget build(BuildContext context) {
    if (businesses.isEmpty) {
      return const _NoResults();
    }

    return GridView.builder(
      itemCount: businesses.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.8,
        crossAxisSpacing: 22,
        mainAxisSpacing: 22,
      ),
      itemBuilder: (context, index) {
        return _BusinessResultTile(business: businesses[index]);
      },
    );
  }
}

class _BusinessResultTile extends StatelessWidget {
  final SearchBusinessApiModel business;

  const _BusinessResultTile({required this.business});

  @override
  Widget build(BuildContext context) {
    return Row(
      textDirection: TextDirection.rtl,
      children: [
        _ResultImage(
          imageUrl: '',
          fallbackText: business.name,
          fallbackIcon: Icons.storefront_outlined,
          color: Color(business.colorValue),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            business.name.isEmpty ? 'متجر' : business.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13, color: Color(0xFF2B2B2B)),
          ),
        ),
      ],
    );
  }
}

class _ResultImage extends StatelessWidget {
  final String imageUrl;
  final IconData fallbackIcon;
  final Color color;
  final String? fallbackText;

  const _ResultImage({
    required this.imageUrl,
    required this.fallbackIcon,
    required this.color,
    this.fallbackText,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 52,
        height: 52,
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
                errorBuilder: (_, __, ___) => Container(
                  color: color,
                  child: Icon(fallbackIcon, color: MerzoxColors.kColor3D5A80),
                ),
              ),
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
            'لا توجد نتائج',
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
