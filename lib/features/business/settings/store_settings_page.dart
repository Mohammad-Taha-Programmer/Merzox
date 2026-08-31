import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/features/business/shell/business_bloc.dart';

/// Store settings flow from the design: one page with the three sections
/// the artboards split across tabs — logo, description, and social links.
class StoreSettingsPage extends StatefulWidget {
  final OwnerBusiness business;

  const StoreSettingsPage({super.key, required this.business});

  @override
  State<StoreSettingsPage> createState() => _StoreSettingsPageState();
}

class _StoreSettingsPageState extends State<StoreSettingsPage> {
  late final TextEditingController _name = TextEditingController(
    text: widget.business.name,
  );
  late final TextEditingController _logoUrl = TextEditingController(
    text: widget.business.logoUrl,
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.business.description,
  );
  late final TextEditingController _address = TextEditingController(
    text: widget.business.address,
  );
  late final TextEditingController _category = TextEditingController(
    text: widget.business.category,
  );
  // Not on any artboard, and here because merchant enrollment collects both
  // and the server accepts edits to both. The old profile dialog was their
  // only editor; routing its menu row to this page would otherwise have
  // stranded two stored fields with no way to correct them.
  late final TextEditingController _englishName = TextEditingController(
    text: widget.business.englishName,
  );
  late final TextEditingController _attachmentUrl = TextEditingController(
    text: widget.business.attachmentUrl,
  );
  late final TextEditingController _instagram = TextEditingController(
    text: widget.business.socialLinks.instagram,
  );
  late final TextEditingController _whatsapp = TextEditingController(
    text: widget.business.socialLinks.whatsapp,
  );
  late final TextEditingController _mobile = TextEditingController(
    text: widget.business.socialLinks.mobile,
  );
  late final TextEditingController _facebook = TextEditingController(
    text: widget.business.socialLinks.facebook,
  );

  @override
  void dispose() {
    for (final controller in [
      _name,
      _logoUrl,
      _description,
      _address,
      _category,
      _englishName,
      _attachmentUrl,
      _instagram,
      _whatsapp,
      _mobile,
      _facebook,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    context.read<BusinessBloc>().add(
      BusinessProfileSaved({
        'name': _name.text.trim(),
        'logoUrl': _logoUrl.text.trim(),
        'description': _description.text.trim(),
        'address': _address.text.trim(),
        'category': _category.text.trim(),
        'englishName': _englishName.text.trim(),
        'attachmentUrl': _attachmentUrl.text.trim(),
        'socialLinks': {
          'instagram': _instagram.text.trim(),
          'whatsapp': _whatsapp.text.trim(),
          'mobile': _mobile.text.trim(),
          'facebook': _facebook.text.trim(),
        },
      }),
    );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('storeSettings.saved'.tr())));
    Navigator.of(context).pop();
  }

  /// Which section is open. The artboards show exactly one at a time, and a
  /// second open section would push the save button off the screen.
  _SettingsSection? _open = _SettingsSection.store;

  void _toggle(_SettingsSection section) =>
      setState(() => _open = _open == section ? null : section);

  @override
  Widget build(BuildContext context) {
    final String logoUrl = _logoUrl.text.trim();

    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: <Widget>[
              SizedBox(
                width: double.infinity,
                height: 66,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Text(
                      'storeSettings.title'.tr(),
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
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  children: <Widget>[
                    _Accordion(
                      title: 'storeSettings.storeDetails'.tr(),
                      open: _open == _SettingsSection.store,
                      onTap: () => _toggle(_SettingsSection.store),
                      children: <Widget>[
                        _Field(
                          controller: _name,
                          label: 'storeSettings.storeNameLabel'.tr(),
                        ),
                      ],
                    ),
                    _Accordion(
                      title: 'storeSettings.logo'.tr(),
                      open: _open == _SettingsSection.logo,
                      onTap: () => _toggle(_SettingsSection.logo),
                      children: <Widget>[
                        Text(
                          'storeSettings.logoAttach'.tr(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            color: MerzoxColors.kColor3B3B3B,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: Container(
                            width: 96,
                            height: 96,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              color: MerzoxColors.kColorF3F7FA,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: MerzoxColors.kColorDEEEF8,
                                width: 2,
                              ),
                            ),
                            child: logoUrl.isEmpty
                                ? const Icon(
                                    Icons.file_upload_outlined,
                                    size: 32,
                                    color: MerzoxColors.kColor98C1D9,
                                  )
                                : Image.network(
                                    logoUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.broken_image_outlined,
                                      size: 30,
                                      color: MerzoxColors.kColorBEBEBE,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        // The artboard states the size it wants rather than
                        // letting a merchant discover it by rejection.
                        Text(
                          'storeSettings.logoSpec'.tr(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            color: MerzoxColors.kColorEE6C4D,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _Field(
                          controller: _logoUrl,
                          label: 'storeSettings.logoHint'.tr(),
                          keyboardType: TextInputType.url,
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                    ),
                    _Accordion(
                      title: 'storeSettings.description'.tr(),
                      open: _open == _SettingsSection.description,
                      onTap: () => _toggle(_SettingsSection.description),
                      children: <Widget>[
                        _Field(
                          controller: _description,
                          label: 'storeSettings.aboutStore'.tr(),
                          maxLines: 4,
                        ),
                        _Field(
                          controller: _address,
                          label: 'storeSettings.addressLabel'.tr(),
                        ),
                        _Field(
                          controller: _category,
                          label: 'storeSettings.categoryLabel'.tr(),
                        ),
                        _Field(
                          controller: _englishName,
                          label: 'business.englishName'.tr(),
                        ),
                        _Field(
                          controller: _attachmentUrl,
                          label: 'business.attachmentUrl'.tr(),
                          keyboardType: TextInputType.url,
                        ),
                      ],
                    ),
                    _Accordion(
                      title: 'storeSettings.socialLinks'.tr(),
                      open: _open == _SettingsSection.social,
                      onTap: () => _toggle(_SettingsSection.social),
                      children: <Widget>[
                        _Field(
                          controller: _instagram,
                          label: 'storeSettings.instagram'.tr(),
                          icon: Icons.camera_alt_outlined,
                        ),
                        _Field(
                          controller: _whatsapp,
                          label: 'storeSettings.whatsapp'.tr(),
                          icon: Icons.chat_outlined,
                          keyboardType: TextInputType.phone,
                        ),
                        _Field(
                          controller: _mobile,
                          label: 'storeSettings.mobile'.tr(),
                          icon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                        ),
                        _Field(
                          controller: _facebook,
                          label: 'storeSettings.facebook'.tr(),
                          icon: Icons.facebook_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: MerzoxColors.kColorEE6C4D,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: Text('common.save'.tr()),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The four sections `اعدادات المتجر` collapses into.
enum _SettingsSection { store, logo, description, social }

/// One collapsible section: a 48-tall row that opens onto its fields.
class _Accordion extends StatelessWidget {
  final String title;
  final bool open;
  final VoidCallback onTap;
  final List<Widget> children;

  const _Accordion({
    required this.title,
    required this.open,
    required this.onTap,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Material(
            color: MerzoxColors.kColorF7F8FA,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 48,
                child: Row(
                  children: <Widget>[
                    const SizedBox(width: 14),
                    Icon(
                      open
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: MerzoxColors.kColor8D99AE,
                    ),
                    Expanded(
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          color: MerzoxColors.kColor3B3B3B,
                        ),
                      ),
                    ),
                    const SizedBox(width: 34),
                  ],
                ),
              ),
            ),
          ),
          if (open) ...<Widget>[const SizedBox(height: 14), ...children],
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final int maxLines;
  final IconData? icon;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  const _Field({
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.icon,
    this.keyboardType,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: icon == null ? null : Icon(icon, size: 18),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        style: const TextStyle(fontSize: 13),
      ),
    );
  }
}
