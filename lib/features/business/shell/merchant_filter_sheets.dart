/// The two filter sheets the merchant browse artboards raise.
///
/// `الرئيسية – 12` filters orders by number, customer, status and a date
/// range; `الرئيسية – 16` filters products by name, classification and
/// visibility. They are drawn identically — same title, same 48-tall bordered
/// fields at a 92 pitch, same 227-wide search button — so the chrome lives in
/// one place and each sheet only names its own fields.
library;

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:merzox/core/constants/colors.dart';

import '../models/business_models.dart';

/// Field metrics, probed one pixel column at a time on both artboards.
const double _kFieldHeight = 48;
const double _kFieldRadius = 6;
const double _kLabelToField = 14;
const double _kFieldPitch = 92;
const double _kGutter = 16;
const Color _kFieldBorder = Color(0xFFCBE0EC);

/// What `الرئيسية – 16` narrows the merchant's own catalogue by.
///
/// Unlike the order filter this never reaches the server: the whole catalogue
/// arrives in one response, so filtering it here is both complete and instant.
final class MerchantProductFilter {
  final String name;

  /// One of the server's classifications, or null for any.
  final String? classification;

  /// True for products on the storefront, false for hidden ones, null for any.
  final bool? visible;

  const MerchantProductFilter({
    this.name = '',
    this.classification,
    this.visible,
  });

  bool get isEmpty => name.isEmpty && classification == null && visible == null;

  /// Applies the filter, plus the browse screen's own search box.
  List<OwnerProduct> apply(List<OwnerProduct> products, {String search = ''}) {
    final String needle = name.trim().toLowerCase();
    final String browse = search.trim().toLowerCase();

    return products.where((OwnerProduct product) {
      if (classification != null && product.classification != classification) {
        return false;
      }
      if (visible != null && product.isActive != visible) return false;
      if (needle.isNotEmpty && !product.name.toLowerCase().contains(needle)) {
        return false;
      }
      if (browse.isNotEmpty &&
          !product.name.toLowerCase().contains(browse) &&
          !product.description.toLowerCase().contains(browse)) {
        return false;
      }
      return true;
    }).toList();
  }
}

/// The sheet chrome: a grab handle, a centred title, the caller's fields and
/// the search button.
class _FilterSheet extends StatelessWidget {
  final List<Widget> fields;
  final VoidCallback onSearch;

  const _FilterSheet({required this.fields, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 16),
            Container(
              width: 110,
              height: 3,
              decoration: BoxDecoration(
                color: MerzoxColors.kColorD8D8D8,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 30),
            Text(
              'businessShell.filterTitle'.tr(),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: MerzoxColors.kColor2B2B2B,
              ),
            ),
            const SizedBox(height: 22),
            ...fields,
            const SizedBox(height: 32),
            SizedBox(
              width: 227,
              height: _kFieldHeight,
              child: FilledButton(
                onPressed: onSearch,
                style: FilledButton.styleFrom(
                  backgroundColor: MerzoxColors.kColorEE6C4D,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(_kFieldRadius),
                  ),
                ),
                child: Text(
                  'common.search'.tr(),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 54),
          ],
        ),
      ),
    );
  }
}

/// One labelled row: a 13 medium label, then a 48-tall bordered box.
class _Field extends StatelessWidget {
  final String label;
  final Widget child;

  const _Field({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _kGutter,
        0,
        _kGutter,
        _kFieldPitch - _kFieldHeight - _kLabelToField - 18,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: MerzoxColors.kColor3B3B3B,
            ),
          ),
          const SizedBox(height: _kLabelToField - 10),
          SizedBox(
            height: _kFieldHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: _kFieldBorder),
                borderRadius: BorderRadius.circular(_kFieldRadius),
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// The placeholder style both sheets use for an empty field.
const TextStyle _kHintStyle = TextStyle(
  fontSize: 12,
  color: MerzoxColors.kColor9F9F9F,
);

const TextStyle _kValueStyle = TextStyle(
  fontSize: 12,
  color: MerzoxColors.kColor2B2B2B,
);

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;

  const _TextField({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    style: _kValueStyle,
    textAlignVertical: TextAlignVertical.center,
    decoration: InputDecoration(
      isCollapsed: true,
      border: InputBorder.none,
      hintText: hint,
      hintStyle: _kHintStyle,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
    ),
  );
}

/// A field that opens a menu rather than a keyboard, drawn as the artboards
/// draw it: the placeholder until something is chosen, then the choice.
class _ChoiceField<T> extends StatelessWidget {
  final String hint;
  final T? value;
  final Map<T, String> options;
  final ValueChanged<T?> onChanged;

  const _ChoiceField({
    required this.hint,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        icon: const Padding(
          padding: EdgeInsetsDirectional.only(end: 14),
          child: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: MerzoxColors.kColor98C1D9,
          ),
        ),
        padding: const EdgeInsetsDirectional.only(start: 14),
        hint: Text(hint, style: _kHintStyle),
        // The artboards offer no "any" row, so clearing a choice is done by
        // picking the same one again rather than by a row that is not drawn.
        items: <DropdownMenuItem<T>>[
          for (final MapEntry<T, String> option in options.entries)
            DropdownMenuItem<T>(
              value: option.key,
              child: Text(option.value, style: _kValueStyle),
            ),
        ],
        onChanged: (T? next) => onChanged(next == value ? null : next),
      ),
    );
  }
}

/// The sheet's `DD . MM . YYYY` box, which opens the platform date picker.
class _DateField extends StatelessWidget {
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  const _DateField({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(_kFieldRadius),
      onTap: () async {
        final DateTime now = DateTime.now();
        final DateTime? picked = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          // Orders cannot predate the shop and cannot be placed tomorrow.
          firstDate: DateTime(2020),
          lastDate: now,
        );
        if (picked != null) onChanged(picked);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                value == null
                    ? 'businessShell.datePlaceholder'.tr()
                    : '${value!.day.toString().padLeft(2, '0')} . '
                          '${value!.month.toString().padLeft(2, '0')} . '
                          '${value!.year}',
                style: value == null ? _kHintStyle : _kValueStyle,
              ),
            ),
            const Icon(
              Icons.calendar_today_outlined,
              size: 16,
              color: MerzoxColors.kColor98C1D9,
            ),
          ],
        ),
      ),
    );
  }
}

/// Raises `الرئيسية – 12`. Resolves to the filter the merchant searched with,
/// or null if they dismissed the sheet.
Future<MerchantOrderFilter?> showMerchantOrderFilterSheet(
  BuildContext context, {
  required MerchantOrderFilter current,
  required Map<String, String> statusLabels,
}) {
  return showModalBottomSheet<MerchantOrderFilter>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    barrierColor: Colors.black38,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (BuildContext sheetContext) =>
        _OrderFilterBody(current: current, statusLabels: statusLabels),
  );
}

class _OrderFilterBody extends StatefulWidget {
  final MerchantOrderFilter current;
  final Map<String, String> statusLabels;

  const _OrderFilterBody({required this.current, required this.statusLabels});

  @override
  State<_OrderFilterBody> createState() => _OrderFilterBodyState();
}

class _OrderFilterBodyState extends State<_OrderFilterBody> {
  late final TextEditingController _number = TextEditingController(
    text: widget.current.orderNumber,
  );
  late final TextEditingController _customer = TextEditingController(
    text: widget.current.customerName,
  );
  late String? _status = widget.current.status;
  late DateTime? _from = widget.current.from;
  late DateTime? _to = widget.current.to;

  @override
  void dispose() {
    _number.dispose();
    _customer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _FilterSheet(
      onSearch: () => Navigator.of(context).pop(
        widget.current.copyWith(
          orderNumber: _number.text.trim(),
          customerName: _customer.text.trim(),
          status: _status,
          clearStatus: _status == null,
          from: _from,
          clearFrom: _from == null,
          to: _to,
          clearTo: _to == null,
        ),
      ),
      fields: <Widget>[
        _Field(
          label: 'businessShell.orderNumber'.tr(),
          child: _TextField(
            controller: _number,
            hint: 'businessShell.orderNumberHint'.tr(),
          ),
        ),
        _Field(
          label: 'businessShell.orderCustomer'.tr(),
          child: _TextField(
            controller: _customer,
            hint: 'businessShell.orderCustomerHint'.tr(),
          ),
        ),
        _Field(
          label: 'businessShell.orderStatus'.tr(),
          child: _ChoiceField<String>(
            hint: 'businessShell.orderStatusHint'.tr(),
            value: _status,
            options: widget.statusLabels,
            onChanged: (String? next) => setState(() => _status = next),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _kGutter),
          child: Row(
            children: <Widget>[
              Expanded(
                child: _Field(
                  label: 'businessShell.dateFrom'.tr(),
                  child: _DateField(
                    value: _from,
                    onChanged: (DateTime? next) => setState(() => _from = next),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Field(
                  label: 'businessShell.dateTo'.tr(),
                  child: _DateField(
                    value: _to,
                    onChanged: (DateTime? next) => setState(() => _to = next),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Raises `الرئيسية – 16`.
Future<MerchantProductFilter?> showMerchantProductFilterSheet(
  BuildContext context, {
  required MerchantProductFilter current,
  required Map<String, String> classificationLabels,
}) {
  return showModalBottomSheet<MerchantProductFilter>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    barrierColor: Colors.black38,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (BuildContext sheetContext) => _ProductFilterBody(
      current: current,
      classificationLabels: classificationLabels,
    ),
  );
}

class _ProductFilterBody extends StatefulWidget {
  final MerchantProductFilter current;
  final Map<String, String> classificationLabels;

  const _ProductFilterBody({
    required this.current,
    required this.classificationLabels,
  });

  @override
  State<_ProductFilterBody> createState() => _ProductFilterBodyState();
}

class _ProductFilterBodyState extends State<_ProductFilterBody> {
  late final TextEditingController _name = TextEditingController(
    text: widget.current.name,
  );
  late String? _classification = widget.current.classification;
  late bool? _visible = widget.current.visible;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _FilterSheet(
      onSearch: () => Navigator.of(context).pop(
        MerchantProductFilter(
          name: _name.text.trim(),
          classification: _classification,
          visible: _visible,
        ),
      ),
      fields: <Widget>[
        _Field(
          label: 'businessShell.productName'.tr(),
          child: _TextField(
            controller: _name,
            hint: 'businessShell.productNameHint'.tr(),
          ),
        ),
        _Field(
          label: 'businessShell.productClassifications'.tr(),
          child: _ChoiceField<String>(
            hint: 'businessShell.productClassificationsHint'.tr(),
            value: _classification,
            options: widget.classificationLabels,
            onChanged: (String? next) => setState(() => _classification = next),
          ),
        ),
        _Field(
          label: 'businessShell.productState'.tr(),
          child: _ChoiceField<bool>(
            hint: 'businessShell.productStateHint'.tr(),
            value: _visible,
            options: <bool, String>{
              true: 'businessShell.published'.tr(),
              false: 'businessShell.hidden'.tr(),
            },
            onChanged: (bool? next) => setState(() => _visible = next),
          ),
        ),
      ],
    );
  }
}
