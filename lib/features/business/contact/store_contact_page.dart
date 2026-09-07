import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/core/widgets/remote_circle_avatar.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/services/api_service.dart';

import 'store_contact_channels.dart';

/// How this shop can be reached.
///
/// There is no board for this screen, so it is built from the ones there are:
/// the profile's rows - a light tile, its icon at the reading edge, a chevron
/// alone at the far one - under the same section labels the settings screen
/// uses. Nothing here is new to look at, which is the point.
///
/// It shows nothing it was not given. A channel that was never filled in has
/// no row at all - a row that led nowhere would be worse than a shorter page.
///
/// Two people arrive here and see the same screen. The merchant reads their
/// own shop out of the account they are signed in as; a customer reads what
/// the server published about somebody else's. So the page is given channels
/// rather than either of those, and neither reader's way in knows how the
/// other one's rows were gathered.
class StoreContactPage extends StatelessWidget {
  /// Whose channels these are.
  final String storeName;
  final String category;
  final String logoUrl;

  final List<StoreContactChannel> social;
  final List<StoreContactChannel> phones;
  final List<StoreContactChannel> emails;

  /// Opens a channel. The default hands it to the system; a test watches
  /// instead of launching a browser.
  final Future<bool> Function(Uri uri)? open;

  /// Where the merchant goes to fill in what is missing. A customer has
  /// nowhere to be sent, so for them this is absent rather than disabled.
  final VoidCallback? onEditSettings;

  /// What an empty page says. The merchant is told what to add; a customer is
  /// told the shop has not said - the same absence, but only one of them can
  /// do anything about it.
  final String emptyMessage;

  const StoreContactPage._({
    required this.storeName,
    required this.category,
    required this.logoUrl,
    required this.social,
    required this.phones,
    required this.emails,
    required this.emptyMessage,
    this.open,
    this.onEditSettings,
    super.key,
  });

  /// The merchant's own shop, gathered from what they are signed in as.
  factory StoreContactPage({
    required OwnerBusiness business,
    required AuthApiUser? account,
    Future<bool> Function(Uri uri)? open,
    VoidCallback? onEditSettings,
    Key? key,
  }) {
    return StoreContactPage._(
      key: key,
      storeName: business.name,
      category: business.category,
      logoUrl: business.logoUrl,
      social: storeSocialChannels(business.socialLinks),
      phones: storePhoneChannels(account),
      emails: storeEmailChannels(account),
      emptyMessage: 'storeContact.empty',
      open: open,
      onEditSettings: onEditSettings,
    );
  }

  /// Somebody else's shop, gathered from what its public detail published.
  ///
  /// The numbers and addresses are here only if the owner turned that on, so
  /// an absent one is a decision rather than a gap - which is why nothing on
  /// this side offers to go and fill it in.
  factory StoreContactPage.forVisitor({
    required String storeName,
    required String category,
    required String logoUrl,
    required BusinessSocialLinks socialLinks,
    required StorePublicContact contact,
    Future<bool> Function(Uri uri)? open,
    Key? key,
  }) {
    return StoreContactPage._(
      key: key,
      storeName: storeName,
      category: category,
      logoUrl: logoUrl,
      social: storeSocialChannels(socialLinks),
      phones: contactPhoneChannels(contact.phones),
      emails: contactEmailChannels(contact.emails),
      emptyMessage: 'storeContact.emptyForVisitor',
      open: open,
    );
  }

  /// Whether there is anything at all to show.
  ///
  /// Read from outside as well: the storefront hides its way in here when
  /// this is true, because a row that opens an empty page is the dead end
  /// this screen refuses to draw one of.
  bool get isEmpty => social.isEmpty && phones.isEmpty && emails.isEmpty;

  Future<void> _open(BuildContext context, Uri uri) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final Future<bool> Function(Uri) launch =
        open ??
        (Uri target) =>
            launchUrl(target, mode: LaunchMode.externalApplication);

    bool opened = false;
    try {
      opened = await launch(uri);
    } catch (_) {
      opened = false;
    }

    // A phone with no WhatsApp, or no mail app, answers no rather than
    // throwing - and silence there would look like a dead row.
    if (opened) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('storeContact.couldNotOpen'.tr())),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          key: const ValueKey<String>('storeContact.back'),
          tooltip: 'common.back'.tr(),
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(
            Icons.chevron_left_rounded,
            color: MerzoxColors.kColor5E5E5E,
            size: 28,
          ),
        ),
        title: Text(
          'businessShell.contactUs'.tr(),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: MerzoxColors.kColor2B2B2B,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: <Widget>[
            _Identity(
              storeName: storeName,
              category: category,
              logoUrl: logoUrl,
            ),
            const SizedBox(height: 20),
            if (isEmpty)
              _NothingYet(
                message: emptyMessage,
                onEditSettings: onEditSettings,
              )
            else ...<Widget>[
              if (social.isNotEmpty)
                _Section(
                  title: 'storeSettings.socialLinks'.tr(),
                  channels: social,
                  onOpen: (Uri uri) => _open(context, uri),
                ),
              if (phones.isNotEmpty)
                _Section(
                  title: 'storeContact.phones'.tr(),
                  channels: phones,
                  onOpen: (Uri uri) => _open(context, uri),
                ),
              if (emails.isNotEmpty)
                _Section(
                  title: 'storeContact.emails'.tr(),
                  channels: emails,
                  onOpen: (Uri uri) => _open(context, uri),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Whose channels these are.
class _Identity extends StatelessWidget {
  final String storeName;
  final String category;
  final String logoUrl;

  const _Identity({
    required this.storeName,
    required this.category,
    required this.logoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        RemoteCircleAvatar(
          url: logoUrl,
          radius: 23,
          backgroundColor: MerzoxColors.kColorDEEEF8,
          fallback: const Icon(
            Icons.storefront_rounded,
            size: 22,
            color: MerzoxColors.kColor3D5A80,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                storeName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: MerzoxColors.kColor2B2B2B,
                ),
              ),
              if (category.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: MerzoxColors.kColor8D99AE,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<StoreContactChannel> channels;
  final void Function(Uri uri) onOpen;

  const _Section({
    required this.title,
    required this.channels,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: MerzoxColors.kColor8D99AE,
            ),
          ),
        ),
        for (final StoreContactChannel channel in channels)
          _ChannelRow(channel: channel, onOpen: () => onOpen(channel.uri)),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// One channel, in the shape the profile's rows already have.
class _ChannelRow extends StatelessWidget {
  final StoreContactChannel channel;
  final VoidCallback onOpen;

  const _ChannelRow({required this.channel, required this.onOpen});

  IconData get _icon => switch (channel.kind) {
    // The same glyphs the settings screen puts beside the same fields, so a
    // merchant recognises what they filled in.
    StoreContactKind.whatsapp => Icons.chat_outlined,
    StoreContactKind.instagram => Icons.camera_alt_outlined,
    StoreContactKind.facebook => Icons.facebook_outlined,
    StoreContactKind.phone => Icons.phone_outlined,
    StoreContactKind.email => Icons.mail_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final String note = channel.note.trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: MerzoxColors.kColorF5F9FC,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          key: ValueKey<String>('storeContact.${channel.kind.name}'),
          onTap: onOpen,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: <Widget>[
                Icon(_icon, size: 20, color: MerzoxColors.kColor3D5A80),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        channel.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        // Left to right whatever the page reads: a number or
                        // an address is read the same way in both languages,
                        // and a `+` at its head belongs at its head.
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.start,
                        style: const TextStyle(
                          fontSize: 13,
                          color: MerzoxColors.kColor2B2B2B,
                        ),
                      ),
                      if (note.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          'profileEdit.contactLabels.$note'.tr(),
                          style: const TextStyle(
                            fontSize: 10,
                            color: MerzoxColors.kColor8D99AE,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: MerzoxColors.kColor98C1D9,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A shop that has given no way to reach it.
class _NothingYet extends StatelessWidget {
  final String message;
  final VoidCallback? onEditSettings;

  const _NothingYet({required this.message, this.onEditSettings});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        const SizedBox(height: 40),
        const Icon(
          Icons.contact_support_outlined,
          size: 40,
          color: MerzoxColors.kColor98C1D9,
        ),
        const SizedBox(height: 12),
        Text(
          message.tr(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            height: 1.6,
            color: MerzoxColors.kColor8D99AE,
          ),
        ),
        if (onEditSettings != null) ...<Widget>[
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey<String>('storeContact.openSettings'),
            onPressed: onEditSettings,
            style: FilledButton.styleFrom(
              backgroundColor: MerzoxColors.kColorEE6C4D,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: Text('storeContact.emptyAction'.tr()),
          ),
        ],
      ],
    );
  }
}
