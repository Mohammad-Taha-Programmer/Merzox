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

  @override
  Widget build(BuildContext context) {
    final logoUrl = _logoUrl.text.trim();

    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: 66,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
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
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  children: [
                    _Section('storeSettings.logo'.tr()),
                    const SizedBox(height: 12),
                    Center(
                      child: Container(
                        width: 96,
                        height: 96,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: MerzoxColors.kColorF3F7FA,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: MerzoxColors.kColorDEEEF8,
                            width: 2,
                          ),
                        ),
                        child: logoUrl.isEmpty
                            ? const Icon(
                                Icons.storefront_rounded,
                                size: 36,
                                color: MerzoxColors.kColor3D5A80,
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
                    const SizedBox(height: 14),
                    _Field(
                      controller: _logoUrl,
                      label: 'storeSettings.logoHint'.tr(),
                      keyboardType: TextInputType.url,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 22),
                    _Section('storeSettings.description'.tr()),
                    const SizedBox(height: 12),
                    _Field(controller: _name, label: 'business.storeName'.tr()),
                    _Field(
                      controller: _description,
                      label: 'storeSettings.description'.tr(),
                      maxLines: 4,
                    ),
                    _Field(
                      controller: _address,
                      label: 'business.address'.tr(),
                    ),
                    _Field(
                      controller: _category,
                      label: 'business.category'.tr(),
                    ),
                    const SizedBox(height: 22),
                    _Section('storeSettings.socialLinks'.tr()),
                    const SizedBox(height: 12),
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
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: MerzoxColors.kColorEE6C4D,
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

class _Section extends StatelessWidget {
  final String title;

  const _Section(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: MerzoxColors.kColor2B2B2B,
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
