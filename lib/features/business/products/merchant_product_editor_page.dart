import 'dart:ui' show PathMetric;

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/core/constants/money.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/features/business/products/merchant_product_options_dialog.dart';
import 'package:merzox/features/business/shell/business_bloc.dart';
import 'package:merzox/features/business/shell/business_navigation_bar.dart';
import 'package:merzox/features/business/shell/merchant_browse_widgets.dart';
import 'package:merzox/features/business/shell/merchant_product_images_page.dart';
import 'package:merzox/features/notifications/widgets/notification_badge_button.dart';

/// `إضافة منتجات` — the merchant's product form, as its three artboards draw
/// it.
///
/// A full page rather than the bottom sheet it used to be: the boards are 1334
/// tall with the shell's own bar drawn across the fold, which is a form the
/// list scrolls under, not a sheet raised over it.
///
/// Two fields have no artboard. `هذا العنصر خدمة` and the per-option price and
/// stock are stored by the server and collected nowhere else, so they stay
/// where the form has room for them rather than becoming values a merchant can
/// hold but never correct.
class MerchantProductEditorPage extends StatefulWidget {
  final OwnerProduct? product;

  /// Where the shell should land if the bottom bar is used to leave.
  final ValueChanged<int>? onTabRequested;

  const MerchantProductEditorPage({
    super.key,
    this.product,
    this.onTabRequested,
  });

  @override
  State<MerchantProductEditorPage> createState() =>
      _MerchantProductEditorPageState();
}

const double _gutter = 17;
const double _fieldHeight = 48;

/// Label baseline to the top of its field, and field to the next label.
const double _labelGap = 10;
const double _groupGap = 16;

class _MerchantProductEditorPageState extends State<MerchantProductEditorPage> {
  static const int _maxVariants = 50;
  static const int _maxVariantLabelLength = 80;

  final GlobalKey<FormState> _key = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _costPrice;
  late final TextEditingController _stockQuantity;
  late final TextEditingController _priceAfterDiscount;
  late final TextEditingController _keywords;

  late List<String> _imageUrls;
  late final List<ProductOptionDraft> _variants;

  late String? _classification;
  late bool _isService;
  late bool _isActive;
  late bool _unlimitedStock;
  late bool _hasDiscount;
  late final int _openedAtRevision;

  bool _submitted = false;

  @override
  void initState() {
    super.initState();

    final OwnerProduct? product = widget.product;

    _name = TextEditingController(text: product?.name ?? '');
    _description = TextEditingController(text: product?.description ?? '');

    _price = TextEditingController(
      text: product == null ? '' : merzoxAmount(product.price),
    );

    _costPrice = TextEditingController(
      text: product?.costPrice == null ? '' : merzoxAmount(product!.costPrice!),
    );

    _stockQuantity = TextEditingController(
      text: product == null || product.unlimitedStock
          ? ''
          : '${product.stockQuantity}',
    );

    // The artboard asks for the price the customer pays, not the percentage
    // off. The server stores the percentage and derives the final price from
    // it, so this is converted on the way in and on the way out and the
    // server's rule is untouched.
    final double percent = product?.discountPercent ?? 0;
    _priceAfterDiscount = TextEditingController(
      text: product == null || percent <= 0
          ? ''
          : merzoxAmount(product.price * (1 - percent / 100)),
    );

    _keywords = TextEditingController(
      text: product == null ? '' : product.keywords.join('، '),
    );

    _imageUrls = List<String>.of(product?.imageUrls ?? const <String>[]);

    _variants =
        product?.variants.map(ProductOptionDraft.fromOwner).toList() ??
        <ProductOptionDraft>[];

    _classification = product?.classification;
    _isService = product?.isService ?? false;
    _isActive = product?.isActive ?? true;
    // The board opens with the box clear and the quantity field showing: a
    // shop states how many it has, and ticks the box when it does not count.
    _unlimitedStock = product?.unlimitedStock ?? false;
    _hasDiscount = percent > 0;

    _openedAtRevision = context.read<BusinessBloc>().state.revision;
  }

  @override
  void dispose() {
    for (final TextEditingController controller in <TextEditingController>[
      _name,
      _description,
      _price,
      _costPrice,
      _stockQuantity,
      _priceAfterDiscount,
      _keywords,
    ]) {
      controller.dispose();
    }

    for (final ProductOptionDraft variant in _variants) {
      variant.dispose();
    }

    super.dispose();
  }

  List<String> _parsedKeywords() => _keywords.text
      .split(RegExp(r'[,،\n]'))
      .map((String keyword) => keyword.trim())
      .where((String keyword) => keyword.isNotEmpty)
      .toList();

  double? get _basePrice => double.tryParse(_price.text.trim());

  Future<void> _manageImages() async {
    final List<String>? next = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute<List<String>>(
        builder: (_) => MerchantProductImagesPage(imageUrls: _imageUrls),
      ),
    );
    if (next == null) return;

    setState(() => _imageUrls = next);
  }

  Future<void> _editOptions() async {
    final List<ProductOptionDraft>? next =
        await showDialog<List<ProductOptionDraft>>(
          context: context,
          // The board dims the form to exactly #9B9B9B over white, which is
          // black at 100/255 - lighter than Material's own barrier.
          barrierColor: const Color(0x64000000),
          builder: (_) => ProductOptionsDialog(
            options: _variants,
            maxOptions: _maxVariants,
            maxLabelLength: _maxVariantLabelLength,
          ),
        );
    if (next == null) return;

    setState(() {
      _variants
        ..clear()
        ..addAll(next);
    });
  }

  double _discountPercentToSend() {
    if (!_hasDiscount) return 0;

    final double? base = _basePrice;
    final double? after = double.tryParse(_priceAfterDiscount.text.trim());

    if (base == null || after == null || base <= 0 || after >= base) return 0;

    return (1 - after / base) * 100;
  }

  Map<String, dynamic> _buildValues() {
    return <String, dynamic>{
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'price': double.parse(_price.text.trim()),
      'costPrice': _costPrice.text.trim().isEmpty
          ? null
          : double.parse(_costPrice.text.trim()),
      'unlimitedStock': _unlimitedStock,
      if (!_unlimitedStock)
        'stockQuantity': int.parse(_stockQuantity.text.trim()),
      'discountPercent': _discountPercentToSend(),
      'keywords': _parsedKeywords(),
      'imageUrls': _imageUrls,
      'classification': _classification ?? 'new',
      'isService': _isService,
      'isActive': _isActive,

      // Existing option-mode products explicitly send [] if every option was
      // removed. New and simple products may omit the field completely.
      if (_variants.isNotEmpty || (widget.product?.hasVariants ?? false))
        'variants': _variants
            .map((ProductOptionDraft variant) => variant.toPayload())
            .toList(),
    };
  }

  void _submit() {
    if (_submitted) return;
    if (_key.currentState?.validate() != true) return;

    setState(() => _submitted = true);

    context.read<BusinessBloc>().add(
      BusinessProductSaved(
        productId: widget.product?.id,
        values: _buildValues(),
      ),
    );
  }

  Future<void> _delete() async {
    final OwnerProduct? product = widget.product;
    if (product == null) {
      Navigator.of(context).pop();
      return;
    }

    await confirmProductDeletion(context, product);
  }

  String? _requiredValidator(String? value) =>
      (value ?? '').trim().isEmpty ? 'merchantProduct.required'.tr() : null;

  String? _positiveNumberValidator(String? value) {
    final double? parsed = double.tryParse((value ?? '').trim());

    if (parsed == null || parsed < 0) {
      return 'merchantProduct.invalidNumber'.tr();
    }

    return null;
  }

  String? _optionalNumberValidator(String? value) =>
      (value ?? '').trim().isEmpty ? null : _positiveNumberValidator(value);

  String? _stockValidator(String? value) {
    final int? parsed = int.tryParse((value ?? '').trim());

    if (parsed == null || parsed < 0) {
      return 'merchantProduct.invalidQuantity'.tr();
    }

    return null;
  }

  /// The discount is entered as the price the customer pays, so it is wrong
  /// exactly when it is not a number below the price it discounts.
  String? _priceAfterDiscountValidator(String? value) {
    final String raw = (value ?? '').trim();
    if (raw.isEmpty) return null;

    final double? after = double.tryParse(raw);
    final double? base = _basePrice;

    if (after == null || after < 0 || base == null || after >= base) {
      return 'merchantProduct.invalidPriceAfterDiscount'.tr();
    }

    return null;
  }

  void _leaveTo(int index) {
    Navigator.of(context).pop();
    widget.onTabRequested?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<BusinessBloc, BusinessState>(
      listenWhen: (BusinessState previous, BusinessState current) =>
          previous.revision != current.revision ||
          previous.status != current.status,
      listener: (BuildContext context, BusinessState state) {
        if (!_submitted) return;

        if (state.revision != _openedAtRevision) {
          Navigator.of(context).pop();

          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(content: Text('merchantProduct.saved'.tr())),
            );

          return;
        }

        if (state.status == BusinessStatus.failure) {
          setState(() => _submitted = false);
        }
      },
      builder: (BuildContext context, BusinessState state) {
        final bool saving = _submitted && state.status == BusinessStatus.saving;

        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: <Widget>[
                MerchantTopBar(
                  title: widget.product == null
                      ? 'merchantProduct.addTitle'.tr()
                      : 'merchantProduct.editTitle'.tr(),
                  leading: NotificationBadgeButton(
                    tooltip: 'notifications.title'.tr(),
                    businessAudience: true,
                    onPressed: () => Navigator.of(context).pop(),
                    iconSize: 24,
                  ),
                ),
                Expanded(
                  child: Form(
                    key: _key,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        _gutter,
                        21,
                        _gutter,
                        28,
                      ),
                      children: <Widget>[
                        _Labelled(
                          label: 'merchantProduct.name'.tr(),
                          child: ProductField(
                            controller: _name,
                            hint: 'merchantProduct.nameHint'.tr(),
                            validator: _requiredValidator,
                          ),
                        ),
                        const SizedBox(height: _groupGap),

                        // Unticking `غير محدودة` is what puts a number here at
                        // all: the artboard drops the field entirely while the
                        // stock is unlimited.
                        _Labelled(
                          label: 'merchantProduct.quantity'.tr(),
                          child: _unlimitedStock
                              ? const SizedBox.shrink()
                              : ProductField(
                                  controller: _stockQuantity,
                                  hint: 'merchantProduct.quantityHint'.tr(),
                                  keyboardType: TextInputType.number,
                                  validator: _stockValidator,
                                ),
                        ),
                        SizedBox(height: _unlimitedStock ? 0 : 9),
                        _CheckRow(
                          label: 'merchantProduct.unlimited'.tr(),
                          value: _unlimitedStock,
                          onChanged: (bool value) =>
                              setState(() => _unlimitedStock = value),
                        ),
                        const SizedBox(height: 15),

                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              child: _Labelled(
                                label: 'merchantProduct.price'.tr(),
                                child: ProductField(
                                  controller: _price,
                                  hint: 'merchantProduct.priceHint'.tr(),
                                  keyboardType: TextInputType.number,
                                  suffix: 'common.currency'.tr(),
                                  validator: _positiveNumberValidator,
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: _Labelled(
                                label: 'merchantProduct.costPrice'.tr(),
                                child: ProductField(
                                  controller: _costPrice,
                                  hint: 'merchantProduct.costPriceHint'.tr(),
                                  keyboardType: TextInputType.number,
                                  validator: _optionalNumberValidator,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _CheckRow(
                          label: 'merchantProduct.hasDiscount'.tr(),
                          value: _hasDiscount,
                          onChanged: (bool value) =>
                              setState(() => _hasDiscount = value),
                        ),
                        if (_hasDiscount) ...<Widget>[
                          const SizedBox(height: _labelGap),
                          ProductField(
                            controller: _priceAfterDiscount,
                            hint: 'merchantProduct.priceAfterDiscount'.tr(),
                            keyboardType: TextInputType.number,
                            suffix: 'common.currency'.tr(),
                            validator: _priceAfterDiscountValidator,
                          ),
                        ],
                        const SizedBox(height: 15),

                        _Labelled(
                          label: 'merchantProduct.classification'.tr(),
                          child: _ClassificationField(
                            value: _classification,
                            onChanged: (String? value) =>
                                setState(() => _classification = value),
                          ),
                        ),
                        const SizedBox(height: _groupGap),

                        _Labelled(
                          label: 'merchantProduct.description'.tr(),
                          child: ProductField(
                            controller: _description,
                            hint: 'merchantProduct.descriptionHint'.tr(),
                            height: 115,
                            maxLines: 5,
                          ),
                        ),
                        const SizedBox(height: 12),

                        _OptionsRow(
                          count: _variants.length,
                          onPressed: _editOptions,
                        ),
                        const SizedBox(height: 14),

                        _Labelled(
                          label: 'merchantProduct.keywords'.tr(),
                          child: ProductField(
                            controller: _keywords,
                            hint: 'merchantProduct.keywordsHint'.tr(),
                            validator: (_) => _parsedKeywords().length > 20
                                ? 'merchantProduct.tooManyKeywords'.tr()
                                : null,
                          ),
                        ),
                        const SizedBox(height: _groupGap),

                        _Labelled(
                          label: 'merchantProduct.images'.tr(),
                          child: _ImagesDropZone(
                            imageUrls: _imageUrls,
                            onPressed: _manageImages,
                          ),
                        ),
                        const SizedBox(height: 7),

                        _PublishRow(
                          value: _isActive,
                          onChanged: (bool value) =>
                              setState(() => _isActive = value),
                        ),
                        const SizedBox(height: 6),
                        _CheckRow(
                          label: 'merchantProduct.isService'.tr(),
                          value: _isService,
                          onChanged: (bool value) =>
                              setState(() => _isService = value),
                        ),
                        const SizedBox(height: 32),

                        _ActionBar(
                          saving: saving,
                          onSave: saving ? null : _submit,
                          onDelete: _delete,
                          deleteEnabled: widget.product != null,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: BusinessNavigationBar(
            selectedIndex: 2,
            onChanged: _leaveTo,
          ),
        );
      },
    );
  }
}

/// `الرئيسية – 15` gates deletion behind a yes/no dialog, which the list it
/// replaces did not: a stray tap on the old menu removed a product outright.
Future<void> confirmProductDeletion(
  BuildContext context,
  OwnerProduct product,
) async {
  final BusinessBloc bloc = context.read<BusinessBloc>();
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      icon: const Icon(
        Icons.error_outline_rounded,
        size: 32,
        color: MerzoxColors.kColorEE6C4D,
      ),
      content: Text(
        'businessShell.deleteProductTitle'.tr(),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: MerzoxColors.kColor2B2B2B,
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: <Widget>[
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: MerzoxColors.kColorEE6C4D,
            fixedSize: const Size(102, 40),
          ),
          child: Text('common.confirm'.tr()),
        ),
        OutlinedButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          style: OutlinedButton.styleFrom(
            foregroundColor: MerzoxColors.kColor2B2B2B,
            fixedSize: const Size(84, 40),
          ),
          child: Text('common.cancel'.tr()),
        ),
      ],
    ),
  );

  if (confirmed ?? false) {
    bloc.add(BusinessProductDeleted(product.id));
  }
}

/// A 13px label over its control, the way every group on the board is set.
class _Labelled extends StatelessWidget {
  final String label;
  final Widget child;

  const _Labelled({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: MerzoxColors.kColor2B2B2B,
          ),
        ),
        const SizedBox(height: _labelGap),
        child,
      ],
    );
  }
}

/// The bordered box every input on the board sits in.
class ProductField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final double height;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? suffix;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final TextAlign textAlign;

  const ProductField({
    super.key,
    required this.controller,
    required this.hint,
    this.height = _fieldHeight,
    this.maxLines = 1,
    this.keyboardType,
    this.suffix,
    this.validator,
    this.onChanged,
    this.textAlign = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      onChanged: onChanged,
      textAlign: textAlign,
      style: const TextStyle(fontSize: 12, color: MerzoxColors.kColor2B2B2B),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          fontSize: 12,
          color: MerzoxColors.kColor9F9F9F,
        ),
        hintTextDirection: Directionality.of(context),
        // The currency sits at the far end of the box on the board, opposite
        // the hint.
        suffixIcon: suffix == null
            ? null
            : Padding(
                padding: const EdgeInsetsDirectional.only(end: 12),
                child: Text(
                  suffix!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: MerzoxColors.kColor9F9F9F,
                  ),
                ),
              ),
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        isDense: true,
        constraints: BoxConstraints(minHeight: height, maxHeight: height),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        border: _border(MerzoxColors.kColorCBE0EC),
        enabledBorder: _border(MerzoxColors.kColorCBE0EC),
        focusedBorder: _border(MerzoxColors.kColor98C1D9),
        errorBorder: _border(MerzoxColors.kColorEE6C4D),
        focusedErrorBorder: _border(MerzoxColors.kColorEE6C4D),
        errorStyle: const TextStyle(fontSize: 10),
      ),
    );
  }

  OutlineInputBorder _border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(5),
    borderSide: BorderSide(color: color),
  );
}

/// A label with a square tick box at the far end, as the board draws it.
class _CheckRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _CheckRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: SizedBox(
        height: 20,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: MerzoxColors.kColor3B3B3B,
                ),
              ),
            ),
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: value ? MerzoxColors.kColor3D5A80 : Colors.white,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: value
                      ? MerzoxColors.kColor3D5A80
                      : MerzoxColors.kColorCBE0EC,
                ),
              ),
              child: value
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ClassificationField extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  const _ClassificationField({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _fieldHeight,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: MerzoxColors.kColorCBE0EC),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: MerzoxColors.kColor9F9F9F,
          ),
          hint: Text(
            'merchantProduct.classificationHint'.tr(),
            style: const TextStyle(
              fontSize: 12,
              color: MerzoxColors.kColor9F9F9F,
            ),
          ),
          style: const TextStyle(
            fontSize: 12,
            fontFamily: 'Tajawal',
            color: MerzoxColors.kColor2B2B2B,
          ),
          items: <String>['new', 'bestSelling', 'offers']
              .map(
                (String key) => DropdownMenuItem<String>(
                  value: key,
                  child: Text('merchantProduct.classifications.$key'.tr()),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// `إضافة خيارات أخرى` and the circled plus that opens the options dialog.
class _OptionsRow extends StatelessWidget {
  final int count;
  final VoidCallback onPressed;

  const _OptionsRow({required this.count, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      child: SizedBox(
        height: 24,
        child: Row(
          children: <Widget>[
            Text(
              'merchantProduct.moreOptions'.tr(),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: MerzoxColors.kColor2B2B2B,
              ),
            ),
            if (count > 0) ...<Widget>[
              const SizedBox(width: 8),
              Text(
                '($count)',
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  fontSize: 12,
                  color: MerzoxColors.kColor9F9F9F,
                ),
              ),
            ],
            const Spacer(),
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: MerzoxColors.kColor98C1D9),
              ),
              child: const Icon(
                Icons.add,
                size: 13,
                color: MerzoxColors.kColor98C1D9,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The dashed panel `الصور` draws.
///
/// It opens the image manager rather than accepting a drop: no upload endpoint
/// exists anywhere in this repository, so a drop target here would be a
/// promise the server cannot keep.
class _ImagesDropZone extends StatelessWidget {
  final List<String> imageUrls;
  final VoidCallback onPressed;

  const _ImagesDropZone({required this.imageUrls, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: CustomPaint(
        painter: _DashedBorderPainter(),
        child: SizedBox(
          height: 125,
          width: double.infinity,
          child: imageUrls.isEmpty
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Icon(
                      Icons.cloud_upload_outlined,
                      size: 42,
                      color: MerzoxColors.kColor98C1D9,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'merchantProduct.imagesDrop'.tr(),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w300,
                        color: MerzoxColors.kColor9F9F9F,
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(12),
                  itemCount: imageUrls.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (BuildContext context, int index) => ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      imageUrls[index],
                      width: 92,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 92,
                        color: MerzoxColors.kColorF3F7FA,
                        child: const Icon(
                          Icons.broken_image_outlined,
                          color: MerzoxColors.kColor98C1D9,
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  static const double _dash = 6;
  static const double _gap = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = MerzoxColors.kColor98C1D9
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final Path outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
          const Radius.circular(6),
        ),
      );

    for (final PathMetric metric in outline.computeMetrics()) {
      double start = 0;
      while (start < metric.length) {
        final double end = start + _dash;
        canvas.drawPath(
          metric.extractPath(start, end.clamp(0, metric.length)),
          paint,
        );
        start = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// `النشر على المتجر`, its switch at the start and the preview link at the end.
class _PublishRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PublishRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 26,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 42,
            child: Transform.scale(
              scale: 0.72,
              child: Switch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: Colors.white,
                activeTrackColor: MerzoxColors.kColorEE6C4D,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'merchantProduct.publish'.tr(),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: MerzoxColors.kColor3B3B3B,
            ),
          ),
          const Spacer(),
          const Icon(
            Icons.visibility_outlined,
            size: 18,
            color: MerzoxColors.kColor8D99AE,
          ),
          const SizedBox(width: 8),
          Text(
            'merchantProduct.preview'.tr(),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: MerzoxColors.kColor3B3B3B,
            ),
          ),
        ],
      ),
    );
  }
}

/// Save and delete as one 48-tall bar, split down the middle.
class _ActionBar extends StatelessWidget {
  final bool saving;
  final VoidCallback? onSave;
  final VoidCallback onDelete;
  final bool deleteEnabled;

  const _ActionBar({
    required this.saving,
    required this.onSave,
    required this.onDelete,
    required this.deleteEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: <Widget>[
          Expanded(
            child: FilledButton(
              onPressed: onSave,
              style: FilledButton.styleFrom(
                backgroundColor: MerzoxColors.kColorEE6C4D,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadiusDirectional.horizontal(
                    start: Radius.circular(5),
                  ),
                ),
              ),
              child: Text(
                saving
                    ? 'merchantProduct.saving'.tr()
                    : 'merchantProduct.save'.tr(),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Expanded(
            child: OutlinedButton(
              onPressed: deleteEnabled ? onDelete : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: MerzoxColors.kColor2B2B2B,
                side: const BorderSide(color: MerzoxColors.kColorCBE0EC),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadiusDirectional.horizontal(
                    end: Radius.circular(5),
                  ),
                ),
              ),
              child: Text(
                'merchantProduct.deleteProduct'.tr(),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
