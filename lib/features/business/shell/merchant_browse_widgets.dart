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

/// The label for one of the server's product classifications.
///
/// The card used to print the stored value, so a product classified `new`
/// read as "new" rather than as the word the artboard shows.
String merchantClassificationLabel(String classification) {
  const Map<String, String> keys = <String, String>{
    'new': 'merchantProduct.classifications.new',
    'bestSelling': 'merchantProduct.classifications.bestSelling',
    'offers': 'merchantProduct.classifications.offers',
  };
  final String? key = keys[classification];

  return key == null ? 'businessShell.unspecified'.tr() : key.tr();
}

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

  /// Whether the sheet behind the button is currently narrowing the list.
  final bool filterIsActive;

  const MerchantSearchRow({
    super.key,
    required this.hint,
    required this.onChanged,
    this.onFilterPressed,
    this.controller,
    this.filterIsActive = false,
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
            _FilterButton(onPressed: onFilterPressed, isActive: filterIsActive),
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
                  // Ten was the artboard's figure and it is not readable on a
                  // phone held at arm's length. Thirteen matches the status
                  // chip beside it, so the row reads at one size.
                  style: const TextStyle(
                    fontSize: 13,
                    color: MerzoxColors.kColor2B2B2B,
                  ),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: hint,
                    hintStyle: const TextStyle(
                      fontSize: 13,
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
  final bool isActive;

  const _FilterButton({this.onPressed, this.isActive = false});

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
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              const Icon(Icons.tune_rounded, size: 22, color: Colors.white),
              if (isActive)
                const PositionedDirectional(
                  end: 6,
                  top: 6,
                  child: _ActiveDot(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The mark on the filter button while a sheet filter is applied.
class _ActiveDot extends StatelessWidget {
  const _ActiveDot();

  @override
  Widget build(BuildContext context) => Container(
    width: 7,
    height: 7,
    decoration: const BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
    ),
  );
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
        // The heading used to be centred with the control pinned past it, so
        // the two drifted together or apart with the heading's length. They
        // sit at opposite ends now: the gap is whatever is left between them,
        // and it is the same row whatever either of them says.
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Flexible(
              child: Text(
                heading,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: MerzoxColors.kColor2B2B2B,
                ),
              ),
            ),
            if (trailing case final Widget control) control,
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
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        labelOf(status),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: MerzoxColors.kColor2B2B2B,
                        ),
                      ),
                    ),
                    // Tapping the status that is already on clears it, which
                    // the menu gave no sign of: it read the same open as
                    // closed, so the way back to every order was something a
                    // merchant had to be told rather than see.
                    if (status == selected)
                      const Icon(
                        Icons.check_rounded,
                        key: ValueKey<String>('merchantStatusFilter.checked'),
                        size: 18,
                        color: MerzoxColors.kColor3D5A80,
                      ),
                  ],
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
  final ValueChanged<MerchantProductAction> onAction;

  const MerchantProductCard({
    super.key,
    required this.product,
    required this.onOpen,
    required this.onAction,
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
                    child: MerchantProductActionsMenu(
                      product: product,
                      onSelected: onAction,
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
          value: merchantClassificationLabel(product.classification),
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
  const _ActionsButton();

  @override
  Widget build(BuildContext context) => Container(
    width: 24,
    height: 24,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: MerzoxColors.kColorEE6C4D,
      borderRadius: BorderRadius.circular(5),
    ),
    child: const Icon(Icons.more_horiz_rounded, size: 16, color: Colors.white),
  );
}

/// What `الرئيسية – 13` offers on one product.
enum MerchantProductAction { edit, show, hide, duplicate, delete }

/// The artboard's action menu, anchored under the card's button.
///
/// Rows are 30 tall with a 10 medium label, which is what the artboard
/// measures; the pair of visibility rows collapses to whichever one is not
/// already true, since the design draws both but only one can ever apply.
class MerchantProductActionsMenu extends StatelessWidget {
  final OwnerProduct product;
  final ValueChanged<MerchantProductAction> onSelected;

  const MerchantProductActionsMenu({
    super.key,
    required this.product,
    required this.onSelected,
  });

  static const double _rowHeight = 30;
  static const double _width = 174;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<MerchantProductAction>(
      tooltip: 'businessShell.editProduct'.tr(),
      position: PopupMenuPosition.under,
      color: Colors.white,
      constraints: const BoxConstraints(minWidth: _width, maxWidth: _width),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: MerzoxColors.kColorEE6C4D),
        borderRadius: BorderRadius.circular(6),
      ),
      onSelected: onSelected,
      itemBuilder: (_) => <PopupMenuEntry<MerchantProductAction>>[
        _row(
          MerchantProductAction.edit,
          'businessShell.editProduct',
          Icons.edit_outlined,
        ),
        if (product.isActive)
          _row(
            MerchantProductAction.hide,
            'businessShell.hideProduct',
            Icons.visibility_off_outlined,
          )
        else
          _row(
            MerchantProductAction.show,
            'businessShell.showProduct',
            Icons.visibility_outlined,
          ),
        _row(
          MerchantProductAction.duplicate,
          'businessShell.duplicateProduct',
          Icons.copy_rounded,
        ),
        _row(
          MerchantProductAction.delete,
          'businessShell.deleteProduct',
          Icons.delete_outline_rounded,
        ),
      ],
      child: const _ActionsButton(),
    );
  }

  PopupMenuItem<MerchantProductAction> _row(
    MerchantProductAction action,
    String label,
    IconData icon,
  ) {
    return PopupMenuItem<MerchantProductAction>(
      value: action,
      height: _rowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: MerzoxColors.kColor98C1D9),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label.tr(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: MerzoxColors.kColor3B3B3B,
              ),
            ),
          ),
        ],
      ),
    );
  }
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

/// The in-app notification strip of `الرئيسية – 17`.
///
/// 48 tall, full width, laid over the list rather than inserted into it: the
/// artboard draws it covering an order row, not displacing one.
class MerchantAlertBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismissed;

  const MerchantAlertBanner({
    super.key,
    required this.message,
    required this.onDismissed,
  });

  static const double height = 48;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey<String>(message),
      direction: DismissDirection.horizontal,
      onDismissed: (_) => onDismissed(),
      child: Container(
        height: height,
        color: MerzoxColors.kColorEE6C4D,
        padding: const EdgeInsets.symmetric(horizontal: 19),
        child: Row(
          children: <Widget>[
            const Icon(
              Icons.star_border_rounded,
              size: 22,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
