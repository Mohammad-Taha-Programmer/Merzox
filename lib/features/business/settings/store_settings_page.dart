import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/core/widgets/merzox_back_chevron.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/core/widgets/merzox_picture_field.dart';
import 'package:merzox/features/business/shell/business_bloc.dart';
import 'package:merzox/services/api_service.dart';

/// Store settings flow from the design: one page with the three sections
/// the artboards split across tabs — logo, description, and social links.
class StoreSettingsPage extends StatefulWidget {
  final OwnerBusiness business;

  /// Injected by tests, which have no server, no camera and no network.
  final ApiService? apiService;
  final AuthSessionService authSessionService;
  final MerzoxPictureDevicePicker? logoDevicePicker;
  final MerzoxPictureLinkReader? logoLinkReader;

  const StoreSettingsPage({
    super.key,
    required this.business,
    this.apiService,
    this.authSessionService = const AuthSessionService(),
    this.logoDevicePicker,
    this.logoLinkReader,
  });

  @override
  State<StoreSettingsPage> createState() => _StoreSettingsPageState();
}

class _StoreSettingsPageState extends State<StoreSettingsPage> {
  late final TextEditingController _name = TextEditingController(
    text: widget.business.name,
  );
  /// The logo as it stands, which the picker replaces.
  ///
  /// Not a controller any more: the link box is gone, and this is set by
  /// uploading rather than by typing.
  late String _logoUrl = widget.business.logoUrl;
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
  late final TextEditingController _facebook = TextEditingController(
    text: widget.business.socialLinks.facebook,
  );

  /// Whether a customer may see the number and address on this account.
  late bool _showOwnerContact = widget.business.showOwnerContact;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _description,
      _address,
      _category,
      _englishName,
      _attachmentUrl,
      _instagram,
      _whatsapp,
      _facebook,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  late final ApiService _api = widget.apiService ?? ApiService();

  /// Stores a chosen logo and answers with where it now lives.
  ///
  /// It goes to the account picture endpoint, which is not a detour: a
  /// merchant has one picture, and the server puts it on the shop they own and
  /// on every conversation that shows it. Setting the shop's logo by itself
  /// would leave a second copy that the next change of picture silently
  /// overwrote.
  ///
  /// That upload also deletes the file it replaces, so a shop that has had
  /// five logos is not paying to keep five.
  Future<String?> _uploadLogo(Uint8List bytes) async {
    final AuthSessionSnapshot session = await widget.authSessionService.read();
    final String? token = session.token;
    if (token == null) throw StateError('Authentication required');

    final AuthApiUser account = await _api.uploadMyAvatar(
      token: token,
      bytes: bytes,
    );

    final String url = account.avatarUrl.trim();
    if (url.isEmpty) return null;

    if (mounted) setState(() => _logoUrl = url);

    // The shell is holding the shop it loaded before this. Reading it again is
    // how the bar, the storefront preview and the inbox pick the new picture
    // up without the merchant having to leave and come back.
    if (mounted) context.read<BusinessBloc>().add(const BusinessRefreshed());

    return url;
  }

  void _save() {
    context.read<BusinessBloc>().add(
      BusinessProfileSaved({
        'name': _name.text.trim(),
        // The logo is not in here. It is stored the moment it is chosen, by
        // the same upload that files it and deletes the one before it, so
        // sending a copy of it back with the rest of the form could only ever
        // undo that.
        'description': _description.text.trim(),
        'address': _address.text.trim(),
        'category': _category.text.trim(),
        'englishName': _englishName.text.trim(),
        'attachmentUrl': _attachmentUrl.text.trim(),
        'socialLinks': {
          'instagram': _instagram.text.trim(),
          'whatsapp': _whatsapp.text.trim(),
          'facebook': _facebook.text.trim(),
        },
        'showOwnerContact': _showOwnerContact,
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
                    // The 40-square target centres the 24-square mark where
                    // the eye already found the arrow it replaces.
                    PositionedDirectional(
                      start: 12,
                      child: MerzoxBackChevronButton(
                        valueKey: const ValueKey<String>('storeSettings.back'),
                        semanticsLabel: 'common.back'.tr(),
                        color: MerzoxColors.kColor5E5E5E,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
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
                          child: MerzoxPictureField(
                            url: _logoUrl,
                            onPicked: _uploadLogo,
                            devicePicker: widget.logoDevicePicker,
                            linkReader: widget.logoLinkReader,
                          ),
                        ),
                        const SizedBox(height: 10),
                        // The artboard states the shape it wants. It used to
                        // state a file size too, which asked a shopkeeper to
                        // know what half a megabyte looks like; the app brings
                        // the picture down itself now, so the demand is gone
                        // and only the shape is left.
                        Text(
                          'storeSettings.logoSpec'.tr(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            color: MerzoxColors.kColorEE6C4D,
                          ),
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
                          controller: _facebook,
                          label: 'storeSettings.facebook'.tr(),
                          icon: Icons.facebook_outlined,
                        ),
                        // Under the links because it answers the same
                        // question - how a customer reaches this shop - and
                        // separate from them because these are not the
                        // shop's to publish without being asked.
                        _PermissionSwitch(
                          value: _showOwnerContact,
                          onChanged: (bool value) =>
                              setState(() => _showOwnerContact = value),
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

/// Whether the account's own number and address go on the storefront.
///
/// Worded as a question about the reader rather than about a setting: what a
/// merchant is deciding is whether a stranger who opens their shop can call
/// the phone in their pocket.
class _PermissionSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PermissionSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: SwitchListTile.adaptive(
        key: const ValueKey<String>('storeSettings.showOwnerContact'),
        value: value,
        onChanged: onChanged,
        contentPadding: EdgeInsets.zero,
        activeThumbColor: MerzoxColors.kColorEE6C4D,
        title: Text(
          'storeSettings.showOwnerContact'.tr(),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: MerzoxColors.kColor2B2B2B,
          ),
        ),
        subtitle: Text(
          'storeSettings.showOwnerContactHint'.tr(),
          style: const TextStyle(
            fontSize: 11,
            height: 1.5,
            color: MerzoxColors.kColor8D99AE,
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

  const _Field({
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.icon,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
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
