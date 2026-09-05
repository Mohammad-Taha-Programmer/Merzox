import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/colors.dart';

/// Where a picked image comes from.
enum AvatarSource { camera, gallery }

/// Picks an image off the device. Named so a test can hand over bytes without
/// a camera, a gallery, or a platform channel.
typedef AvatarPicker = Future<Uint8List?> Function(AvatarSource source);

/// The account's picture in the merchant's top bar.
///
/// It was a fixed storefront glyph: every merchant's bar looked like every
/// other merchant's. It shows the account's own picture now, cropped to the
/// circle the bar draws, and it is its own control - the board offers no
/// other way in.
///
/// Two gestures, and which is which matters. A tap opens the picture large,
/// because looking at it is the common thing and forty pixels is not enough
/// to see a portrait by. Replacing it is rarer and cannot be undone once the
/// old file is deleted, so it takes a deliberate press rather than a stray
/// touch on a control that sits beside the notification bell.
///
/// An account with no picture, or one whose picture will not load, keeps the
/// old glyph. A broken-image box would be worse than the placeholder it
/// replaced.
class MerchantAvatarButton extends StatefulWidget {
  final String avatarUrl;

  /// Uploads the chosen bytes and completes when the account has them.
  final Future<void> Function(Uint8List bytes) onPicked;

  /// Reads an image off the device. The default asks the platform; a test
  /// passes its own.
  final AvatarPicker? picker;

  final double radius;

  const MerchantAvatarButton({
    required this.avatarUrl,
    required this.onPicked,
    this.picker,
    this.radius = 20,
    super.key,
  });

  @override
  State<MerchantAvatarButton> createState() => _MerchantAvatarButtonState();
}

class _MerchantAvatarButtonState extends State<MerchantAvatarButton> {
  bool _busy = false;

  /// True once the picture has failed to load, so the placeholder is drawn
  /// instead of a broken box.
  bool _unloadable = false;

  @override
  void didUpdateWidget(MerchantAvatarButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new URL deserves a fresh attempt: the old one failing says nothing
    // about this one.
    if (oldWidget.avatarUrl != widget.avatarUrl) _unloadable = false;
  }

  Future<Uint8List?> _pickFromDevice(AvatarSource source) async {
    final XFile? file = await ImagePicker().pickImage(
      source: source == AvatarSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      // The picture is drawn in a 40-pixel circle. Sending a 12-megapixel
      // original would spend the merchant's data on detail nothing can show,
      // and the server refuses anything over five megabytes anyway.
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );

    return file?.readAsBytes();
  }

  Future<AvatarSource?> _askSource() {
    return showModalBottomSheet<AvatarSource>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              key: const ValueKey<String>('merchantAvatar.camera'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text('profileEdit.avatarFromCamera'.tr()),
              onTap: () => Navigator.of(sheetContext).pop(AvatarSource.camera),
            ),
            ListTile(
              key: const ValueKey<String>('merchantAvatar.gallery'),
              leading: const Icon(Icons.photo_library_outlined),
              title: Text('profileEdit.avatarFromGallery'.tr()),
              onTap: () => Navigator.of(sheetContext).pop(AvatarSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Opens the picture at a size a portrait can be judged at.
  Future<void> _enlarge() {
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: GestureDetector(
          // Anywhere on it closes: there is nothing to do here but look.
          onTap: () => Navigator.of(dialogContext).pop(),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              widget.avatarUrl,
              key: const ValueKey<String>('merchantAvatar.enlarged'),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const ColoredBox(
                color: Colors.white,
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Icon(
                    Icons.broken_image_outlined,
                    size: 48,
                    color: MerzoxColors.kColor8D99AE,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _replace() async {
    // A second tap while the first is still uploading would send the same
    // picture twice and race over which one lands.
    if (_busy) return;

    final AvatarSource? source = await _askSource();
    if (source == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final Uint8List? bytes = await (widget.picker ?? _pickFromDevice)(source);
      // Backing out of the picker is not a failure and says nothing.
      if (bytes == null) return;

      await widget.onPicked(bytes);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double size = widget.radius * 2;
    final bool showPicture = widget.avatarUrl.isNotEmpty && !_unloadable;

    return Semantics(
      button: true,
      label: 'profileEdit.holdToChangeAvatar'.tr(),
      child: Tooltip(
        message: 'profileEdit.holdToChangeAvatar'.tr(),
        child: InkWell(
          key: const ValueKey<String>('merchantAvatar.button'),
          // Nothing to enlarge when there is no picture, and opening an empty
          // box would be a worse answer than doing nothing.
          onTap: showPicture ? _enlarge : null,
          onLongPress: _replace,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: size,
            height: size,
            child: ClipOval(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  ColoredBox(
                    color: Colors.white,
                    child: showPicture
                        ? Image.network(
                            widget.avatarUrl,
                            key: const ValueKey<String>('merchantAvatar.image'),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) {
                              // Rebuilding during a build is not allowed, so
                              // the fallback is armed for the next frame.
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) {
                                  setState(() => _unloadable = true);
                                }
                              });
                              return _placeholder();
                            },
                          )
                        : _placeholder(),
                  ),
                  if (_busy)
                    ColoredBox(
                      color: Colors.black.withValues(alpha: 0.45),
                      child: const Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
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

  /// The glyph the bar drew before there were pictures.
  ///
  /// Its size is left to the ambient icon theme rather than tied to [radius],
  /// which is what the `CircleAvatar` this replaced did - so an account with
  /// no picture looks exactly as it always has.
  Widget _placeholder() => const Center(
    child: Icon(Icons.storefront_rounded, color: MerzoxColors.kColor3D5A80),
  );
}
