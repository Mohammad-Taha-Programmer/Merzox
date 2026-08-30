/// The chrome the two merchant browse artboards share.
///
/// `الرئيسية – 9` (orders) and `الرئيسية – 10` (products) draw the same three
/// bands above their list — a titled top bar, a search row and a section row —
/// so they live here once rather than twice inside the shell page.
///
/// Every constant below is a measurement, not a preference: the artboards were
/// exported to SVG, the text nodes read for their own font size and colour, and
/// the boxes probed one pixel column at a time.
library;

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/core/constants/money.dart';

import '../models/business_models.dart';

/// Both artboards inset their content 16 from each edge.
const double kMerchantGutter = 16;

/// Top bar: title baseline at y=75 over a 44-tall status bar.
const double kMerchantTopBarHeight = 48;

/// Search row: y=113..160 on both artboards.
const double kMerchantSearchRowHeight = 48;
const double kMerchantTopBarToSearch = 21;

/// Section row: the orders artboard's status chip spans y=186..219.
const double kMerchantSectionRowHeight = 34;
const double kMerchantSearchToSection = 25;

/// The bar above the list, with the screen's title and one leading action.
///
/// The artboards place the title left of centre with no rule that both of them
/// agree on — their titles differ by 10px of ink and 4.6px of right edge — so
/// it is centred here, the way every other Merzox top bar centres its title.
class MerchantTopBar extends StatelessWidget {
  final String title;
  final Widget leading;

  const MerchantTopBar({super.key, required this.title, required this.leading});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kMerchantTopBarHeight,
      child: Stack(
        children: <Widget>[
          Center(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: MerzoxColors.kColor2B2B2B,
              ),
            ),
          ),
          PositionedDirectional(
            end: kMerchantGutter,
            top: 0,
            bottom: 0,
            child: Center(child: leading),
          ),
        ],
      ),
    );
  }
}

/// The filter button and the search field, as one 48-tall row.
///
/// The filter button is a 48x48 square at the gutter, then 16 of gap, then the
/// field fills the rest — 279 wide on a 375 artboard, which is what `Expanded`
/// produces on any width.
class MerchantSearchRow extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback? onFilterPressed;
  final TextEditingController? controller;

  const MerchantSearchRow({
    super.key,
    required this.hint,
    required this.onChanged,
    this.onFilterPressed,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kMerchantGutter),
      child: SizedBox(
        height: kMerchantSearchRowHeight,
        child: Row(
          // The artboards put the orange square on the left and the field on
          // the right in Arabic, so this row keeps that order in both locales.
          textDirection: TextDirection.ltr,
          children: <Widget>[
            _FilterButton(onPressed: onFilterPressed),
            const SizedBox(width: 16),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: MerzoxColors.kColorF9F9F9,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  textAlignVertical: TextAlignVertical.center,
                  style: const TextStyle(
                    fontSize: 10,
                    color: MerzoxColors.kColor2B2B2B,
                  ),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: hint,
                    hintStyle: const TextStyle(
                      fontSize: 10,
                      color: MerzoxColors.kColorC7C7C7,
                    ),
                    contentPadding: const EdgeInsetsDirectional.fromSTEB(
                      12,
                      0,
                      18,
                      0,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: MerzoxColors.kColor2B2B2B,
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 38,
                      minHeight: 20,
                    ),
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

/// The orange square left of the search field.
///
/// The artboards give it the same 48x48 box as the field beside it, which is
/// why it is sized rather than left to an [IconButton]'s own metrics.
class _FilterButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const _FilterButton({this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kMerchantSearchRowHeight,
      height: kMerchantSearchRowHeight,
      child: Material(
        color: MerzoxColors.kColorEE6C4D,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: const Icon(Icons.tune_rounded, size: 22, color: Colors.white),
        ),
      ),
    );
  }
}

/// The "all orders" / "all products" line, with whatever the artboard puts on
/// the far side of it.
class MerchantSectionRow extends StatelessWidget {
  final String heading;
  final Widget? trailing;

  const MerchantSectionRow({super.key, required this.heading, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kMerchantGutter),
      child: SizedBox(
        height: kMerchantSectionRowHeight,
        child: Stack(
          children: <Widget>[
            Center(
              child: Text(
                heading,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: MerzoxColors.kColor2B2B2B,
                ),
              ),
            ),
            if (trailing != null)
              PositionedDirectional(
                end: 0,
                top: 0,
                bottom: 0,
                child: Center(child: trailing!),
              ),
          ],
        ),
      ),
    );
  }
}

/// The status filter, drawn as a 116x34 chip in `الرئيسية – 9`.
///
/// The label reads "order status" until a status is picked, which is what the
/// artboard shows; picking one replaces it with that status's own name, and
/// picking it again clears the filter.
class MerchantStatusFilterChip extends StatelessWidget {
  final String? selected;
  final List<String> options;
  final String Function(String status) labelOf;
  final ValueChanged<String?> onSelected;

  const MerchantStatusFilterChip({
    super.key,
    required this.selected,
    required this.options,
    required this.labelOf,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 116,
      height: 34,
      child: Material(
        color: MerzoxColors.kColor98C1D9,
        borderRadius: BorderRadius.circular(6),
        child: PopupMenuButton<String>(
          tooltip: 'businessShell.orderStatus'.tr(),
          position: PopupMenuPosition.under,
          onSelected: (String value) =>
              onSelected(value == selected ? null : value),
          itemBuilder: (_) => <PopupMenuEntry<String>>[
            for (final String status in options)
              PopupMenuItem<String>(
                value: status,
                height: 34,
                child: Text(
                  labelOf(status),
                  style: const TextStyle(
                    fontSize: 13,
                    color: MerzoxColors.kColor2B2B2B,
                  ),
                ),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: Colors.white,
                ),
                Expanded(
                  child: Text(
                    selected == null
                        ? 'businessShell.orderStatus'.tr()
                        : labelOf(selected!),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One row of the merchant product list, as `الرئيسية – 10` draws it.
///
/// 343x127 with an 84x95 photo inset 16 on the leading side, three text lines
/// down the middle, an action button in the trailing top corner and, when the
/// product is live, the artboard's blue "published" corner.
class MerchantProductCard extends StatelessWidget {
  final OwnerProduct product;
  final VoidCallback onOpen;
  final VoidCallback onActionsPressed;

  const MerchantProductCard({
    super.key,
    required this.product,
    required this.onOpen,
    required this.onActionsPressed,
  });

  static const double height = 127;
  static const double photoWidth = 84;
  static const double photoHeight = 95;
  static const double inset = 16;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: height,
              child: Stack(
                children: <Widget>[
                  if (product.isActive) const _PublishedCorner(),
                  PositionedDirectional(
                    start: inset,
                    top: inset,
                    child: _Photo(product: product),
                  ),
                  PositionedDirectional(
                    start: inset + photoWidth + 12,
                    end: inset + 24 + 12,
                    top: inset,
                    bottom: inset,
                    child: _Details(product: product),
                  ),
                  PositionedDirectional(
                    end: 10,
                    top: 10,
                    child: _ActionsButton(onPressed: onActionsPressed),
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

class _Photo extends StatelessWidget {
  final OwnerProduct product;

  const _Photo({required this.product});

  @override
  Widget build(BuildContext context) {
    final String url = product.imageUrls.isEmpty ? '' : product.imageUrls.first;

    return SizedBox(
      width: MerchantProductCard.photoWidth,
      height: MerchantProductCard.photoHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: url.isEmpty
                  ? const ColoredBox(
                      color: MerzoxColors.kColorDEEEF8,
                      child: Icon(Icons.inventory_2_outlined),
                    )
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
            ),
          ),
          const PositionedDirectional(end: -4, top: -4, child: _PhotoBadge()),
        ],
      ),
    );
  }
}

/// The orange disc the artboard sets on every product photo.
///
/// It carries no action of its own: the whole card opens the editor, and this
/// sits inside that tap target rather than claiming a second one.
class _PhotoBadge extends StatelessWidget {
  const _PhotoBadge();

  @override
  Widget build(BuildContext context) => Container(
    width: 18,
    height: 18,
    decoration: const BoxDecoration(
      color: MerzoxColors.kColorEE6C4D,
      shape: BoxShape.circle,
    ),
    child: const Icon(Icons.add_rounded, size: 13, color: Colors.white),
  );
}

class _Details extends StatelessWidget {
  final OwnerProduct product;

  const _Details({required this.product});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          product.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: MerzoxColors.kColor2B2B2B,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: _Field(
                label: 'businessShell.orderPrice'.tr(),
                value: merzoxAmount(product.price),
              ),
            ),
            Expanded(
              child: _Field(
                label: 'businessShell.productQuantity'.tr(),
                // An unlimited-stock product has no quantity to show, and the
                // artboard has no cell for that case, so the dash stands in
                // rather than a zero that would read as "sold out".
                value: product.unlimitedStock
                    ? '—'
                    : product.stockQuantity.toString(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _Field(
          label: 'businessShell.productClassification'.tr(),
          value: product.classification.isEmpty
              ? 'businessShell.unspecified'.tr()
              : product.classification,
        ),
      ],
    );
  }
}

/// A label at 10 medium beside its value at 14 bold, the pairing the artboard
/// uses for price, quantity and classification alike.
class _Field extends StatelessWidget {
  final String label;
  final String value;

  const _Field({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: MerzoxColors.kColor3B3B3B,
        ),
      ),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: MerzoxColors.kColor3B3B3B,
          ),
        ),
      ),
    ],
  );
}

class _ActionsButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _ActionsButton({required this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 24,
    height: 24,
    child: Material(
      color: MerzoxColors.kColorEE6C4D,
      borderRadius: BorderRadius.circular(5),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(5),
        child: const Icon(
          Icons.more_horiz_rounded,
          size: 16,
          color: Colors.white,
        ),
      ),
    ),
  );
}

/// The blue quarter-disc in the card's trailing bottom corner.
///
/// The artboard places its "published" label off the card entirely — only the
/// last glyph survives the clip — so the word is drawn inside the disc here,
/// which is the one part of this element the design leaves unreadable.
class _PublishedCorner extends StatelessWidget {
  const _PublishedCorner();

  @override
  Widget build(BuildContext context) => PositionedDirectional(
    end: 0,
    bottom: 0,
    child: SizedBox(
      width: 52,
      height: 29,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: MerzoxColors.kColor98C1D9,
          borderRadius: BorderRadiusDirectional.only(
            topStart: Radius.circular(29),
          ),
        ),
        child: Align(
          alignment: AlignmentDirectional.bottomEnd,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 6, bottom: 6),
            child: Text(
              'businessShell.published'.tr(),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
