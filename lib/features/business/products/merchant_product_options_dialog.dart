import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/core/constants/money.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/features/business/products/merchant_product_editor_page.dart';

/// One product option being edited — `الخيار1` on the artboard, a variant to
/// the server.
///
/// The artboard's dialog names options and nothing else, but a variant also
/// carries its own price, cost, stock and availability. Those are kept on the
/// draft and edited from the chip, because a product that already has them
/// would otherwise lose them the next time it was saved.
final class ProductOptionDraft {
  final String? id;
  final TextEditingController label;
  final TextEditingController priceOverride;
  final TextEditingController costPrice;
  final TextEditingController stockQuantity;

  bool unlimitedStock;
  bool isActive;

  ProductOptionDraft({
    required this.id,
    required this.label,
    required this.priceOverride,
    required this.costPrice,
    required this.stockQuantity,
    required this.unlimitedStock,
    required this.isActive,
  });

  factory ProductOptionDraft.named(String label) {
    return ProductOptionDraft(
      id: null,
      label: TextEditingController(text: label),
      priceOverride: TextEditingController(),
      costPrice: TextEditingController(),
      stockQuantity: TextEditingController(),
      unlimitedStock: true,
      isActive: true,
    );
  }

  factory ProductOptionDraft.fromOwner(OwnerProductVariant variant) {
    return ProductOptionDraft(
      id: variant.id,
      label: TextEditingController(text: variant.label),
      priceOverride: TextEditingController(
        text: variant.priceOverride == null
            ? ''
            : merzoxAmount(variant.priceOverride!),
      ),
      costPrice: TextEditingController(
        text: variant.costPrice == null ? '' : merzoxAmount(variant.costPrice!),
      ),
      stockQuantity: TextEditingController(
        text: variant.unlimitedStock ? '' : '${variant.stockQuantity}',
      ),
      unlimitedStock: variant.unlimitedStock,
      isActive: variant.isActive,
    );
  }

  double? _optionalDouble(TextEditingController controller) {
    final String raw = controller.text.trim();
    return raw.isEmpty ? null : double.tryParse(raw);
  }

  Map<String, dynamic> toPayload() {
    return OwnerProductVariantDraft(
      id: id,
      label: label.text.trim(),
      priceOverride: _optionalDouble(priceOverride),
      costPrice: _optionalDouble(costPrice),
      stockQuantity: unlimitedStock
          ? 0
          : int.tryParse(stockQuantity.text.trim()) ?? 0,
      unlimitedStock: unlimitedStock,
      isActive: isActive,
    ).toJson();
  }

  void dispose() {
    label.dispose();
    priceOverride.dispose();
    costPrice.dispose();
    stockQuantity.dispose();
  }
}

/// `خيارات إضافية للمنتج` — name an option, add it, and it becomes a chip.
class ProductOptionsDialog extends StatefulWidget {
  final List<ProductOptionDraft> options;
  final int maxOptions;
  final int maxLabelLength;

  const ProductOptionsDialog({
    super.key,
    required this.options,
    required this.maxOptions,
    required this.maxLabelLength,
  });

  @override
  State<ProductOptionsDialog> createState() => _ProductOptionsDialogState();
}

class _ProductOptionsDialogState extends State<ProductOptionsDialog> {
  final TextEditingController _name = TextEditingController();

  late final List<ProductOptionDraft> _options = List<ProductOptionDraft>.of(
    widget.options,
  );

  String _error = '';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _add() {
    final String label = _name.text.trim();

    if (label.isEmpty || label.length > widget.maxLabelLength) {
      setState(() => _error = 'merchantProduct.invalidVariantLabel'.tr());
      return;
    }

    final String normalized = label.toLowerCase();
    final bool duplicate = _options.any(
      (ProductOptionDraft option) =>
          option.label.text.trim().toLowerCase() == normalized,
    );

    if (duplicate) {
      setState(() => _error = 'merchantProduct.duplicateVariantLabel'.tr());
      return;
    }

    if (_options.length >= widget.maxOptions) {
      setState(() => _error = 'merchantProduct.variantLimit'.tr());
      return;
    }

    setState(() {
      _options.add(ProductOptionDraft.named(label));
      _name.clear();
      _error = '';
    });
  }

  Future<void> _openDetails(ProductOptionDraft option) async {
    final bool? removed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _OptionDetailsSheet(option: option),
    );

    if (removed ?? false) {
      setState(() {
        _options.remove(option);
        option.dispose();
      });
      return;
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // The board rests the panel's foot on the bottom bar rather than centring
    // it in the screen, which also keeps a dialog that is mostly a text field
    // and a button within reach of a thumb. The keyboard's own inset is added
    // so it lifts clear rather than being covered by what it is typed into.
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Dialog(
      backgroundColor: Colors.white,
      alignment: Alignment.bottomCenter,
      insetPadding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 24,
        bottom: 76 + keyboard,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Stack(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 27, 16, 64),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'merchantProduct.optionsTitle'.tr(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: MerzoxColors.kColor2B2B2B,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'merchantProduct.optionsBody'.tr(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.9,
                    color: MerzoxColors.kColor3B3B3B,
                  ),
                ),
                const SizedBox(height: 24),
                ProductField(
                  controller: _name,
                  hint: 'merchantProduct.optionNameHint'.tr(),
                  textAlign: TextAlign.center,
                ),
                if (_error.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    _error,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      color: MerzoxColors.kColorEE6C4D,
                    ),
                  ),
                ],
                const SizedBox(height: 17),
                SizedBox(
                  height: 48,
                  child: Row(
                    children: <Widget>[
                      // The board reads options first and the plus last, so
                      // the newest chip lands beside the button that made it.
                      Expanded(
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _options.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 16),
                          itemBuilder: (BuildContext context, int index) =>
                              _OptionChip(
                                option: _options[index],
                                onPressed: () => _openDetails(_options[index]),
                              ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      _AddOptionButton(onPressed: _add),
                    ],
                  ),
                ),
                const SizedBox(height: 55),
                SizedBox(
                  height: 48,
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(_options),
                          style: FilledButton.styleFrom(
                            backgroundColor: MerzoxColors.kColorEE6C4D,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                          child: Text(
                            'merchantProduct.save'.tr(),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _add,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: MerzoxColors.kColor2B2B2B,
                            side: const BorderSide(
                              color: MerzoxColors.kColorCBE0EC,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                          child: Text(
                            'merchantProduct.addOptions'.tr(),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
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
          PositionedDirectional(
            end: 9,
            top: 9,
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              customBorder: const CircleBorder(),
              child: Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: MerzoxColors.kColor98C1D9,
                ),
                child: const Icon(Icons.close, size: 12, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddOptionButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _AddOptionButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: MerzoxColors.kColor3D5A80,
        borderRadius: BorderRadius.circular(5),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: const Icon(Icons.add, size: 22, color: Colors.white),
        ),
      ),
    );
  }
}

class _OptionChip extends StatelessWidget {
  final ProductOptionDraft option;
  final VoidCallback onPressed;

  const _OptionChip({required this.option, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        height: 48,
        constraints: const BoxConstraints(minWidth: 48),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: MerzoxColors.kColorCBE0EC),
        ),
        child: Text(
          option.label.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            color: MerzoxColors.kColor9F9F9F,
          ),
        ),
      ),
    );
  }
}

/// What a chip hides: the option's own price, cost, stock and availability.
class _OptionDetailsSheet extends StatefulWidget {
  final ProductOptionDraft option;

  const _OptionDetailsSheet({required this.option});

  @override
  State<_OptionDetailsSheet> createState() => _OptionDetailsSheetState();
}

class _OptionDetailsSheetState extends State<_OptionDetailsSheet> {
  @override
  Widget build(BuildContext context) {
    final ProductOptionDraft option = widget.option;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        18,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 22,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              option.label.text,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            Text(
              'merchantProduct.priceOverride'.tr(),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            ProductField(
              controller: option.priceOverride,
              hint: 'merchantProduct.priceOverrideHint'.tr(),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 14),
            Text(
              'merchantProduct.costPrice'.tr(),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            ProductField(
              controller: option.costPrice,
              hint: 'merchantProduct.costPriceHint'.tr(),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 14),
            SwitchListTile(
              value: option.unlimitedStock,
              onChanged: (bool value) =>
                  setState(() => option.unlimitedStock = value),
              title: Text('merchantProduct.unlimited'.tr()),
              contentPadding: EdgeInsets.zero,
            ),
            if (!option.unlimitedStock) ...<Widget>[
              ProductField(
                controller: option.stockQuantity,
                hint: 'merchantProduct.quantityHint'.tr(),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 14),
            ],
            SwitchListTile(
              value: option.isActive,
              onChanged: (bool value) =>
                  setState(() => option.isActive = value),
              title: Text('merchantProduct.variantActive'.tr()),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              style: OutlinedButton.styleFrom(
                foregroundColor: MerzoxColors.kColorEE6C4D,
              ),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: Text('merchantProduct.removeVariant'.tr()),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: FilledButton.styleFrom(
                backgroundColor: MerzoxColors.kColorEE6C4D,
              ),
              child: Text('common.done'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
