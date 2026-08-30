import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/core/localization/api_error_localizer.dart';
import 'package:merzox/services/api_service.dart';

/// The address form of `تفاصيل المتجر – 25`, with the pickers of `– 27` and
/// `– 28`.
///
/// The form validates nothing the server does not also validate. What it does
/// is refuse to *offer* what the server would reject: a closed governorate is
/// shown and disabled rather than hidden, so a customer can see their city
/// exists and is not served yet, and the city list only ever holds cities of
/// the governorate above it.
class AddressFormPage extends StatefulWidget {
  /// Null when adding; the address being edited otherwise.
  final SavedAddressApiModel? existing;

  final String token;
  final ApiService? apiService;

  const AddressFormPage({
    super.key,
    required this.token,
    this.existing,
    this.apiService,
  });

  @override
  State<AddressFormPage> createState() => _AddressFormPageState();
}

class _AddressFormPageState extends State<AddressFormPage> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();

  late final TextEditingController _fullName = TextEditingController(
    text: widget.existing?.fullName ?? '',
  );
  late final TextEditingController _phone = TextEditingController(
    text: widget.existing?.phone ?? '',
  );
  late final TextEditingController _altPhone = TextEditingController(
    text: widget.existing?.altPhone ?? '',
  );
  late final TextEditingController _details = TextEditingController(
    text: widget.existing?.details ?? '',
  );

  late String? _governorate = widget.existing?.governorate;
  late String? _city = widget.existing?.city;
  late bool _isDefault = widget.existing?.isDefault ?? false;

  List<DeliveryRegionApiModel> _regions = const <DeliveryRegionApiModel>[];
  bool _saving = false;
  String _error = '';

  ApiService get _api => widget.apiService ?? ApiService();

  @override
  void initState() {
    super.initState();
    _loadRegions();
  }

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    _altPhone.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _loadRegions() async {
    try {
      final List<DeliveryRegionApiModel> regions = await _api.deliveryRegions();
      if (mounted) setState(() => _regions = regions);
    } catch (_) {
      // The form still submits: the server validates the pair regardless, so
      // an unreachable region list costs the pickers, not correctness.
    }
  }

  DeliveryRegionApiModel? get _selectedRegion {
    for (final DeliveryRegionApiModel region in _regions) {
      if (region.governorate == _governorate) return region;
    }

    return null;
  }

  Future<void> _submit() async {
    if (_form.currentState?.validate() != true) return;
    if (_governorate == null || _city == null) {
      setState(() => _error = 'address.regionRequired'.tr());
      return;
    }

    setState(() {
      _saving = true;
      _error = '';
    });

    final Map<String, dynamic> payload = <String, dynamic>{
      'fullName': _fullName.text.trim(),
      'phone': _phone.text.trim(),
      'altPhone': _altPhone.text.trim(),
      'governorate': _governorate,
      'city': _city,
      'details': _details.text.trim(),
      'isDefault': _isDefault,
    };

    try {
      final List<SavedAddressApiModel> addresses = widget.existing == null
          ? await _api.createAddress(token: widget.token, address: payload)
          : await _api.updateAddress(
              token: widget.token,
              addressId: widget.existing!.id,
              address: payload,
            );

      if (mounted) Navigator.of(context).pop(addresses);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = localizeApiErrorOrRaw(ApiService.messageFromError(error));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          (widget.existing == null ? 'address.addTitle' : 'address.editTitle')
              .tr(),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: MerzoxColors.kColor2B2B2B,
          ),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: <Widget>[
            _Field(
              label: 'address.fullName'.tr(),
              child: TextFormField(
                controller: _fullName,
                decoration: _decoration('address.fullNameHint'.tr()),
                validator: (String? value) => (value ?? '').trim().length < 2
                    ? 'address.fullNameInvalid'.tr()
                    : null,
              ),
            ),
            _Field(
              label: 'address.phone'.tr(),
              child: TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: _decoration('address.phoneHint'.tr()),
                validator: _phoneValidator,
              ),
            ),
            _Field(
              label: 'address.governorate'.tr(),
              child: _RegionPicker(
                hint: 'address.governorateHint'.tr(),
                value: _governorate,
                entries: <_PickerEntry>[
                  for (final DeliveryRegionApiModel region in _regions)
                    _PickerEntry(
                      value: region.governorate,
                      // Closed governorates are shown and disabled, so the
                      // customer sees the place exists and is not served.
                      enabled: region.open,
                    ),
                ],
                onChanged: (String value) => setState(() {
                  _governorate = value;
                  _city = null;
                }),
              ),
            ),
            _Field(
              label: 'address.city'.tr(),
              child: _RegionPicker(
                hint: 'address.cityHint'.tr(),
                value: _city,
                entries: <_PickerEntry>[
                  for (final String city in _selectedRegion?.cities ?? const [])
                    _PickerEntry(value: city, enabled: true),
                ],
                onChanged: (String value) => setState(() => _city = value),
              ),
            ),
            _Field(
              label: 'address.details'.tr(),
              child: TextFormField(
                controller: _details,
                maxLength: 250,
                decoration: _decoration('address.detailsHint'.tr()),
              ),
            ),
            _Field(
              label: 'address.altPhone'.tr(),
              child: TextFormField(
                controller: _altPhone,
                keyboardType: TextInputType.phone,
                decoration: _decoration('address.altPhoneHint'.tr()),
                validator: (String? value) => (value ?? '').trim().isEmpty
                    ? null
                    : _phoneValidator(value),
              ),
            ),
            CheckboxListTile(
              value: _isDefault,
              onChanged: (bool? value) =>
                  setState(() => _isDefault = value ?? false),
              controlAffinity: ListTileControlAffinity.trailing,
              contentPadding: EdgeInsets.zero,
              activeColor: MerzoxColors.kColor3D5A80,
              title: Text(
                'address.makeDefault'.tr(),
                style: const TextStyle(fontSize: 12),
              ),
            ),
            if (_error.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _error,
                style: const TextStyle(
                  fontSize: 12,
                  color: MerzoxColors.kColorB72D2D,
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _saving ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: MerzoxColors.kColorEE6C4D,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: Text(
                  'common.save'.tr(),
                  style: const TextStyle(fontSize: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Mirrors the server's rule rather than inventing a stricter one.
  String? _phoneValidator(String? value) {
    final RegExp pattern = RegExp(r'^\+?[0-9]{7,15}$');

    return pattern.hasMatch((value ?? '').trim())
        ? null
        : 'address.phoneInvalid'.tr();
  }

  InputDecoration _decoration(String hint) => InputDecoration(
    hintText: hint,
    counterText: '',
    hintStyle: const TextStyle(fontSize: 12, color: MerzoxColors.kColor9F9F9F),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: const BorderSide(color: Color(0xFFCBE0EC)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: const BorderSide(color: MerzoxColors.kColor98C1D9),
    ),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
  );
}

class _Field extends StatelessWidget {
  final String label;
  final Widget child;

  const _Field({required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
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
        const SizedBox(height: 6),
        child,
      ],
    ),
  );
}

final class _PickerEntry {
  final String value;
  final bool enabled;

  const _PickerEntry({required this.value, required this.enabled});
}

/// The radio list of `تفاصيل المتجر – 27` and `– 28`, raised as a sheet.
class _RegionPicker extends StatelessWidget {
  final String hint;
  final String? value;
  final List<_PickerEntry> entries;
  final ValueChanged<String> onChanged;

  const _RegionPicker({
    required this.hint,
    required this.value,
    required this.entries,
    required this.onChanged,
  });

  Future<void> _open(BuildContext context) async {
    if (entries.isEmpty) return;

    final String? picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      barrierColor: Colors.black38,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext sheetContext) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: <Widget>[
              for (final _PickerEntry entry in entries)
                ListTile(
                  enabled: entry.enabled,
                  onTap: () => Navigator.of(sheetContext).pop(entry.value),
                  leading: Icon(
                    entry.value == value
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: entry.enabled
                        ? MerzoxColors.kColor3D5A80
                        : MerzoxColors.kColorBEBEBE,
                  ),
                  title: Text(
                    entry.value,
                    style: TextStyle(
                      fontSize: 13,
                      color: entry.enabled
                          ? MerzoxColors.kColor2B2B2B
                          : MerzoxColors.kColorBEBEBE,
                    ),
                  ),
                  // The artboard tags an unserved governorate «مغلق» rather
                  // than dropping it from the list.
                  trailing: entry.enabled
                      ? null
                      : Text(
                          'address.closed'.tr(),
                          style: const TextStyle(
                            fontSize: 11,
                            color: MerzoxColors.kColorBEBEBE,
                          ),
                        ),
                ),
            ],
          ),
        ),
      ),
    );

    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _open(context),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFCBE0EC)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                value ?? hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: value == null
                      ? MerzoxColors.kColor9F9F9F
                      : MerzoxColors.kColor2B2B2B,
                ),
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: MerzoxColors.kColor98C1D9,
            ),
          ],
        ),
      ),
    );
  }
}
