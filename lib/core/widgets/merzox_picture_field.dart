import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:merzox/core/constants/colors.dart';

/// Where a picture comes from.
///
/// The same three the product images screen offers, because somebody who
/// already hosts their artwork elsewhere should not have to re-upload it, and
/// somebody who has it on their phone should not have to host it first.
enum MerzoxPictureSource { camera, gallery, link }

/// Reads an image off the device. A test hands over bytes instead of standing
/// up a camera.
typedef MerzoxPictureDevicePicker =
    Future<Uint8List?> Function(MerzoxPictureSource source);

/// Fetches the bytes behind a pasted link.
typedef MerzoxPictureLinkReader = Future<Uint8List?> Function(String url);

/// The side of the box the store-settings artboard draws.
const double kStoreLogoBox = 96;

/// As much of a pasted image as is worth downloading.
///
/// The server refuses more than five megabytes, so anything past that would be
/// carried across the reader's connection only to be turned away at the end
/// of it.
const int kMerzoxPictureMaxBytes = 5 * 1024 * 1024;

/// Downloads a pasted image, or gives up quietly.
///
/// The app fetches the link rather than handing it to the server, and that is
/// deliberate: the bytes then travel the same road as a photograph from the
/// camera, so all three ways end at one upload, one stored file, and one
/// picture that can be replaced and deleted like any other. A link kept as a
/// link would be none of those - it could not be resized, it could not be
/// removed, and it would go dark the day its host did.
Future<Uint8List?> fetchPictureBytes(String url, {Dio? dio}) async {
  final Uri? parsed = Uri.tryParse(url.trim());

  if (parsed == null ||
      !parsed.hasScheme ||
      (parsed.scheme != 'http' && parsed.scheme != 'https') ||
      parsed.host.isEmpty) {
    return null;
  }

  final Response<List<int>> response = await (dio ?? Dio()).getUri<List<int>>(
    parsed,
    options: Options(
      responseType: ResponseType.bytes,
      receiveTimeout: const Duration(seconds: 20),
      // A page that says "not found" is still a 200 on some hosts; the type is
      // what says whether this is a picture.
      validateStatus: (int? status) => status != null && status < 400,
    ),
  );

  final String type =
      response.headers.value(Headers.contentTypeHeader)?.toLowerCase() ?? '';
  if (!type.startsWith('image/')) return null;

  final List<int>? body = response.data;
  if (body == null || body.isEmpty || body.length > kMerzoxPictureMaxBytes) {
    return null;
  }

  return Uint8List.fromList(body);
}

/// A picture, and the three ways to change it.
///
/// A tap opens it large, because looking at it is the common thing and the
/// space a screen gives it is not enough to judge artwork by. Replacing it is
/// rarer and cannot be undone once the old file is deleted, so it takes a
/// deliberate press - except when there is no picture yet, where a tap opens
/// the picker, since there is nothing to enlarge and the empty frame is an
/// invitation.
///
/// Two screens draw this: the shop's logo, as a square the settings board
/// sets, and the account's own picture, as the circle the profile board sets.
/// Only the frame differs, so only the frame is a parameter.
class MerzoxPictureField extends StatefulWidget {
  final String url;

  /// Uploads the chosen bytes and answers with the URL the picture now lives
  /// at, or null if it could not be stored.
  final Future<String?> Function(Uint8List bytes) onPicked;

  final MerzoxPictureDevicePicker? devicePicker;
  final MerzoxPictureLinkReader? linkReader;

  /// How the frame is drawn, and how large.
  final BoxShape shape;
  final double size;

  /// What stands in the frame before there is a picture.
  final Widget? placeholder;

  /// Read out loud, and shown on a long press.
  final String hintKey;

  /// Names this instance's parts for a test. The sheet and the dialog are
  /// routes and only one is ever open, so they keep one set of names; the
  /// frame and the picture belong to whichever screen drew them.
  final String keyPrefix;

  const MerzoxPictureField({
    required this.url,
    required this.onPicked,
    this.devicePicker,
    this.linkReader,
    this.shape = BoxShape.rectangle,
    this.size = kStoreLogoBox,
    this.placeholder,
    this.hintKey = 'storeSettings.logoChangeHint',
    this.keyPrefix = 'storeLogo',
    super.key,
  });

  @override
  State<MerzoxPictureField> createState() => _MerzoxPictureFieldState();
}

class _MerzoxPictureFieldState extends State<MerzoxPictureField> {
  bool _busy = false;

  /// True once the picture has failed to load, so the empty frame is drawn
  /// rather than a broken one.
  bool _unloadable = false;

  @override
  void didUpdateWidget(MerzoxPictureField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new URL deserves a fresh attempt: the old one failing says nothing
    // about this one.
    if (oldWidget.url != widget.url) _unloadable = false;
  }

  Future<Uint8List?> _pickFromDevice(MerzoxPictureSource source) async {
    final XFile? file = await ImagePicker().pickImage(
      source: source == MerzoxPictureSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      // Brought down before it leaves the phone, so the reader does not spend
      // their data on detail a small picture has no use for. The host trims it
      // again on the way in; this is the part that saves the upload.
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );

    return file?.readAsBytes();
  }

  Future<MerzoxPictureSource?> _askSource() {
    return showModalBottomSheet<MerzoxPictureSource>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 8),
            Text(
              'merchantImages.sourceTitle'.tr(),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: MerzoxColors.kColor2B2B2B,
              ),
            ),
            ListTile(
              key: const ValueKey<String>('storeLogo.camera'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text('merchantImages.sourceCamera'.tr()),
              onTap: () =>
                  Navigator.of(sheetContext).pop(MerzoxPictureSource.camera),
            ),
            ListTile(
              key: const ValueKey<String>('storeLogo.gallery'),
              leading: const Icon(Icons.photo_library_outlined),
              title: Text('merchantImages.sourceGallery'.tr()),
              onTap: () =>
                  Navigator.of(sheetContext).pop(MerzoxPictureSource.gallery),
            ),
            ListTile(
              key: const ValueKey<String>('storeLogo.link'),
              leading: const Icon(Icons.link_rounded),
              title: Text('merchantImages.sourceLink'.tr()),
              onTap: () =>
                  Navigator.of(sheetContext).pop(MerzoxPictureSource.link),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<String?> _askLink() {
    return showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => const _PictureLinkDialog(),
    );
  }

  /// Opens the picture at a size the artwork can be judged at.
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
              widget.url,
              key: const ValueKey<String>('storeLogo.enlarged'),
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
    // A second press while the first is still uploading would send two
    // pictures and race over which one lands.
    if (_busy) return;

    final MerzoxPictureSource? source = await _askSource();
    if (source == null || !mounted) return;

    String? link;
    if (source == MerzoxPictureSource.link) {
      link = await _askLink();
      if (link == null || link.trim().isEmpty || !mounted) return;
    }

    setState(() => _busy = true);
    try {
      final Uint8List? bytes = source == MerzoxPictureSource.link
          ? await (widget.linkReader ?? fetchPictureBytes)(link!)
          : await (widget.devicePicker ?? _pickFromDevice)(source);

      if (!mounted) return;

      // Backing out of the picker is not a failure and says nothing. A link
      // that gave nothing back is a failure, and does.
      if (bytes == null) {
        if (source == MerzoxPictureSource.link) {
          _report('merchantImages.uploadFailed'.tr());
        }
        return;
      }

      final String? url = await widget.onPicked(bytes);
      if (!mounted) return;

      if (url == null || url.isEmpty) {
        _report('merchantImages.uploadFailed'.tr());
      }
    } catch (_) {
      if (mounted) _report('merchantImages.uploadFailed'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _report(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  bool get _round => widget.shape == BoxShape.circle;

  BorderRadius? get _radius =>
      _round ? null : BorderRadius.circular(8);

  @override
  Widget build(BuildContext context) {
    final String url = widget.url.trim();
    final bool showPicture = url.isNotEmpty && !_unloadable;

    return Semantics(
      button: true,
      label: widget.hintKey.tr(),
      child: Tooltip(
        message: widget.hintKey.tr(),
        child: InkWell(
          key: ValueKey<String>('${widget.keyPrefix}.box'),
          // With no picture there is nothing to enlarge, and an empty frame
          // that did nothing when tapped would be a dead end.
          onTap: showPicture ? _enlarge : _replace,
          onLongPress: _replace,
          customBorder: _round ? const CircleBorder() : null,
          borderRadius: _radius,
          child: Container(
            width: widget.size,
            height: widget.size,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: MerzoxColors.kColorF3F7FA,
              shape: widget.shape,
              borderRadius: _radius,
              border: _round
                  ? null
                  : Border.all(color: MerzoxColors.kColorDEEEF8, width: 2),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (showPicture)
                  Image.network(
                    url,
                    key: ValueKey<String>('${widget.keyPrefix}.image'),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) {
                      // Rebuilding during a build is not allowed, so the
                      // fallback is armed for the next frame.
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _unloadable = true);
                      });
                      return _empty();
                    },
                  )
                else
                  _empty(),
                if (_busy)
                  ColoredBox(
                    color: Colors.black.withValues(alpha: 0.45),
                    child: const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
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
    );
  }

  /// The frame as the board draws it before there is a picture.
  Widget _empty() => Center(
    key: ValueKey<String>('${widget.keyPrefix}.placeholder'),
    child:
        widget.placeholder ??
        const Icon(
          Icons.file_upload_outlined,
          size: 32,
          color: MerzoxColors.kColor98C1D9,
        ),
  );
}

/// Asks for the link, and refuses anything that is not one.
class _PictureLinkDialog extends StatefulWidget {
  const _PictureLinkDialog();

  @override
  State<_PictureLinkDialog> createState() => _PictureLinkDialogState();
}

class _PictureLinkDialogState extends State<_PictureLinkDialog> {
  final TextEditingController _url = TextEditingController();
  final GlobalKey<FormState> _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  /// Only an absolute http(s) URL. A relative path or a `javascript:` string
  /// would be fetched by nothing and stored as a picture by mistake.
  String? _validate(String? value) {
    final Uri? parsed = Uri.tryParse((value ?? '').trim());
    final bool usable =
        parsed != null &&
        parsed.hasScheme &&
        (parsed.scheme == 'http' || parsed.scheme == 'https') &&
        parsed.host.isNotEmpty;

    return usable ? null : 'merchantImages.urlInvalid'.tr();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: Text(
        'merchantImages.sourceLink'.tr(),
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      content: Form(
        key: _form,
        child: TextFormField(
          key: const ValueKey<String>('storeLogo.linkField'),
          controller: _url,
          autofocus: true,
          keyboardType: TextInputType.url,
          validator: _validate,
          decoration: InputDecoration(
            hintText: 'merchantImages.urlHint'.tr(),
            hintStyle: const TextStyle(color: MerzoxColors.kColor9F9F9F),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          key: const ValueKey<String>('storeLogo.linkConfirm'),
          onPressed: () {
            if (_form.currentState?.validate() != true) return;
            Navigator.of(context).pop(_url.text.trim());
          },
          style: FilledButton.styleFrom(
            backgroundColor: MerzoxColors.kColorEE6C4D,
          ),
          child: Text('common.save'.tr()),
        ),
      ],
    );
  }
}
