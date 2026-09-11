import 'dart:typed_data';
import 'dart:ui' show PathMetric;

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/core/localization/api_error_localizer.dart';
import 'package:merzox/core/widgets/merzox_icons.dart';
import 'package:merzox/services/api_service.dart';

/// The product image manager of `الرئيسية – 14`.
///
/// The artboard draws a drop target above a list of images, each with its own
/// delete and crop controls and a "primary image" radio, and a save button at
/// the foot. Every box below is measured from it: the 155-tall drop target,
/// the 235-tall preview, the 41-tall control bar under it and the 48-tall
/// button.
///
/// The target used to ask for a link and nothing else, because nothing in this
/// system could take a file: no upload route, no object storage. That is no
/// longer true - the same image host the profile picture uses takes these too
/// - so the box now offers the phone as well as a link, and its wording is the
/// artboard's again.
///
/// The bytes go through the server rather than to the host directly: the
/// host's key is a secret and an app cannot keep one.
///
/// The artboard's crop control is still absent. Cropping needs an editor, not
/// an upload, and drawing a control that does nothing is the defect this just
/// stopped having.
class MerchantProductImagesPage extends StatefulWidget {
  final List<String> imageUrls;

  /// Injected by tests, which have no server and no photo library.
  final ApiService? apiService;
  final AuthSessionService authSessionService;
  final Future<Uint8List?> Function(ImageSource source)? pickImage;

  const MerchantProductImagesPage({
    super.key,
    required this.imageUrls,
    this.apiService,
    this.authSessionService = const AuthSessionService(),
    this.pickImage,
  });

  @override
  State<MerchantProductImagesPage> createState() =>
      _MerchantProductImagesPageState();
}

/// `الرئيسية – 14` draws a drag-and-drop area titled «إضافة صور أو فيديو».
///
/// Neither half of that is available here. The product has no file upload of
/// any kind - no picker, no multipart route, no storage - and no video
/// anywhere: not a field, not a player, not another board. An image is added
/// by its link, which is what the hint says and what the title now says too.
/// Promising a video the product cannot take would be the same defect as a
/// discard button that discards nothing.
class _MerchantProductImagesPageState extends State<MerchantProductImagesPage> {
  static const double _dropTargetHeight = 155;
  static const double _previewHeight = 235;
  static const double _barHeight = 41;
  static const double _gutter = 16;

  late final List<String> _images = List<String>.of(widget.imageUrls);

  /// The storefront shows a product's first image, so "primary" is position
  /// rather than a flag: choosing one moves it to the front.
  void _makePrimary(int index) {
    if (index == 0) return;
    setState(() {
      final String moved = _images.removeAt(index);
      _images.insert(0, moved);
    });
  }

  /// True while bytes are on their way to the image host.
  bool _uploading = false;

  late final ApiService _api = widget.apiService ?? ApiService();

  Future<Uint8List?> _pick(ImageSource source) async {
    if (widget.pickImage != null) return widget.pickImage!(source);

    final XFile? file = await ImagePicker().pickImage(
      source: source,
      // A product photo is shown at most a screen wide. Sending a
      // twelve-megapixel original would spend the merchant's data on detail
      // nothing renders, and the server refuses anything over five megabytes.
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );

    return file?.readAsBytes();
  }

  Future<void> _add() async {
    final _ImageSourceChoice? choice =
        await showModalBottomSheet<_ImageSourceChoice>(
          context: context,
          builder: (BuildContext sheetContext) => const _SourceSheet(),
        );

    if (choice == null || !mounted) return;

    if (choice == _ImageSourceChoice.link) {
      await _addByLink();
      return;
    }

    await _addFromDevice(
      choice == _ImageSourceChoice.camera
          ? ImageSource.camera
          : ImageSource.gallery,
    );
  }

  Future<void> _addByLink() async {
    final String? url = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => const _AddImageDialog(),
    );
    final String trimmed = url?.trim() ?? '';
    if (trimmed.isEmpty || !mounted) return;

    setState(() => _images.add(trimmed));
  }

  Future<void> _addFromDevice(ImageSource source) async {
    final Uint8List? bytes = await _pick(source);
    if (bytes == null || !mounted) return;

    setState(() => _uploading = true);

    try {
      final AuthSessionSnapshot session = await widget.authSessionService
          .read();
      final String? token = session.token;
      if (token == null) throw StateError('Authentication required');

      final String url = await _api.uploadProductImage(
        token: token,
        bytes: bytes,
      );

      if (!mounted) return;
      // An empty URL is a server that answered without giving us the one thing
      // the request was for; adding it would put a broken image in the list.
      if (url.isEmpty) {
        _reportFailure('merchantImages.uploadFailed'.tr());
        return;
      }

      setState(() => _images.add(url));
    } catch (error) {
      if (!mounted) return;
      _reportFailure(localizeApiErrorOrRaw(ApiService.messageFromError(error)));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _reportFailure(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: Text(
          'merchantImages.title'.tr(),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: MerzoxColors.kColor2B2B2B,
          ),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'common.cancel'.tr(),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(
              Icons.cancel_outlined,
              color: MerzoxColors.kColorBEBEBE,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(_gutter, 0, _gutter, 24),
        children: <Widget>[
          _DropTarget(
            height: _dropTargetHeight,
            onTap: _uploading ? null : _add,
            busy: _uploading,
          ),
          const SizedBox(height: 26),
          for (int index = 0; index < _images.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _ImageEntry(
                url: _images[index],
                isPrimary: index == 0,
                previewHeight: _previewHeight,
                barHeight: _barHeight,
                onMakePrimary: () => _makePrimary(index),
                onRemove: () => setState(() => _images.removeAt(index)),
              ),
            ),
          const SizedBox(height: 28),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(_images),
              style: FilledButton.styleFrom(
                backgroundColor: MerzoxColors.kColorEE6C4D,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: Text(
                'common.save'.tr(),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The artboard's dashed box with its cloud glyph.
/// What the reader chose to add a picture from.
enum _ImageSourceChoice { camera, gallery, link }

/// The three ways in, offered before anything is asked for.
///
/// A link still works: a merchant who already hosts their catalogue elsewhere
/// should not have to re-upload it to use this screen.
class _SourceSheet extends StatelessWidget {
  const _SourceSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
            key: const ValueKey<String>('merchantImages.camera'),
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text('merchantImages.sourceCamera'.tr()),
            onTap: () => Navigator.of(context).pop(_ImageSourceChoice.camera),
          ),
          ListTile(
            key: const ValueKey<String>('merchantImages.gallery'),
            leading: const Icon(Icons.photo_library_outlined),
            title: Text('merchantImages.sourceGallery'.tr()),
            onTap: () => Navigator.of(context).pop(_ImageSourceChoice.gallery),
          ),
          ListTile(
            key: const ValueKey<String>('merchantImages.link'),
            leading: const Icon(Icons.link_rounded),
            title: Text('merchantImages.sourceLink'.tr()),
            onTap: () => Navigator.of(context).pop(_ImageSourceChoice.link),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _DropTarget extends StatelessWidget {
  final double height;
  final VoidCallback? onTap;

  /// While bytes are in flight the target says so and refuses a second tap,
  /// so an impatient merchant does not upload the same photo twice.
  final bool busy;

  const _DropTarget({
    required this.height,
    required this.onTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: CustomPaint(
        painter: const _DashedBorderPainter(),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (busy)
                const SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(strokeWidth: 3),
                )
              else
                Icon(
                  MerzoxIcons.uploadProductImage,
                  size: 44 * MerzoxIcons.uploadProductImageSizeFactor,
                  color: MerzoxColors.kColor98C1D9,
                ),
              const SizedBox(height: 14),
              Text(
                busy
                    ? 'merchantImages.uploading'.tr()
                    : 'merchantImages.addHint'.tr(),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w300,
                  color: MerzoxColors.kColor9F9F9F,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = MerzoxColors.kColor98C1D9
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    const double dash = 6;
    const double gap = 5;
    final RRect box = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(8),
    );
    final Path path = Path()..addRRect(box);

    for (final PathMetric metric in path.computeMetrics()) {
      double start = 0;
      while (start < metric.length) {
        final double end = start + dash;
        canvas.drawPath(
          metric.extractPath(start, end.clamp(0, metric.length)),
          paint,
        );
        start = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) => false;
}

/// One image: the preview, then the artboard's control bar under it.
class _ImageEntry extends StatelessWidget {
  final String url;
  final bool isPrimary;
  final double previewHeight;
  final double barHeight;
  final VoidCallback onMakePrimary;
  final VoidCallback onRemove;

  const _ImageEntry({
    required this.url,
    required this.isPrimary,
    required this.previewHeight,
    required this.barHeight,
    required this.onMakePrimary,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          height: previewHeight,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            child: Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const ColoredBox(
                color: MerzoxColors.kColorDEEEF8,
                child: Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
        ),
        Container(
          height: barHeight,
          color: MerzoxColors.kColorEEF6FB,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: <Widget>[
              IconButton(
                tooltip: 'common.delete'.tr(),
                onPressed: onRemove,
                iconSize: 18 * MerzoxIcons.deleteProductSizeFactor,
                color: MerzoxColors.kColor3B3B3B,
                icon: const Icon(MerzoxIcons.deleteProductForever),
              ),
              const Spacer(),
              Text(
                'merchantImages.primary'.tr(),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: MerzoxColors.kColor3B3B3B,
                ),
              ),
              const SizedBox(width: 12),
              // Exactly one image is primary, and choosing another one is
              // how this one stops being it — so a radio, not a checkbox.
              _PrimaryRadio(selected: isPrimary, onTap: onMakePrimary),
            ],
          ),
        ),
      ],
    );
  }
}

/// The artboard's selection circle: an outline that fills when chosen.
class _PrimaryRadio extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;

  const _PrimaryRadio({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: selected,
      inMutuallyExclusiveGroup: true,
      label: 'merchantImages.primary'.tr(),
      child: InkResponse(
        onTap: selected ? null : onTap,
        radius: 20,
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? MerzoxColors.kColor029DD5 : Colors.transparent,
            border: Border.all(
              color: selected
                  ? MerzoxColors.kColor029DD5
                  : MerzoxColors.kColorBEBEBE,
            ),
          ),
          child: selected
              ? const Icon(Icons.check, size: 12, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

class _AddImageDialog extends StatefulWidget {
  const _AddImageDialog();

  @override
  State<_AddImageDialog> createState() => _AddImageDialogState();
}

class _AddImageDialogState extends State<_AddImageDialog> {
  final TextEditingController _url = TextEditingController();
  final GlobalKey<FormState> _key = GlobalKey<FormState>();

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  /// Only an absolute http(s) URL: a relative path or a `javascript:` string
  /// would be stored and later handed to `Image.network` on every device that
  /// opens the product.
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
        'merchantImages.addTitle'.tr(),
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      content: Form(
        key: _key,
        child: TextFormField(
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
          onPressed: () {
            if (_key.currentState?.validate() != true) return;
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
