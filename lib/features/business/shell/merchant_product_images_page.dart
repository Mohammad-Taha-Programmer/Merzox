import 'dart:ui' show PathMetric;

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:merzox/core/constants/colors.dart';

/// The product image manager of `الرئيسية – 14`.
///
/// The artboard draws a drop target above a list of images, each with its own
/// delete and crop controls and a "primary image" radio, and a save button at
/// the foot. Every box below is measured from it: the 155-tall drop target,
/// the 235-tall preview, the 41-tall control bar under it and the 48-tall
/// button.
///
/// **One deliberate departure.** The artboard's target reads "drag and drop
/// images here", and nothing in this system can accept a dropped file: there
/// is no upload endpoint, no object storage and no multipart route anywhere in
/// the backend, and a product's images are stored as URLs. Rather than draw a
/// target that silently does nothing, the box asks for an image link — the one
/// thing the API can actually store. When an upload path exists this widget is
/// where it lands, and its wording goes back to the artboard's.
///
/// The artboard's crop control is likewise absent, for the same reason: with
/// no bytes of our own to crop, there is nothing for it to act on.
class MerchantProductImagesPage extends StatefulWidget {
  final List<String> imageUrls;

  const MerchantProductImagesPage({super.key, required this.imageUrls});

  @override
  State<MerchantProductImagesPage> createState() =>
      _MerchantProductImagesPageState();
}

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

  Future<void> _add() async {
    final String? url = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => const _AddImageDialog(),
    );
    final String trimmed = url?.trim() ?? '';
    if (trimmed.isEmpty) return;

    setState(() => _images.add(trimmed));
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
          _DropTarget(height: _dropTargetHeight, onTap: _add),
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
class _DropTarget extends StatelessWidget {
  final double height;
  final VoidCallback onTap;

  const _DropTarget({required this.height, required this.onTap});

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
              const Icon(
                Icons.cloud_upload_outlined,
                size: 44,
                color: MerzoxColors.kColor98C1D9,
              ),
              const SizedBox(height: 14),
              Text(
                'merchantImages.addHint'.tr(),
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
              errorBuilder: (_, __, ___) => const ColoredBox(
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
                iconSize: 18,
                color: MerzoxColors.kColor3B3B3B,
                icon: const Icon(Icons.delete_outline_rounded),
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
