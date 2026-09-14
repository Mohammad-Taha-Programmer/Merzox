import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// A picture, as large as the screen will draw it.
///
/// Opened over whatever is underneath rather than pushed as a page: looking
/// closely at a picture is not somewhere a reader has gone, and it should not
/// be somewhere the back button has to bring them out of twice.

const Key kPictureViewerKey = ValueKey<String>('merzox.pictureViewer');
const Key kPictureViewerCloseKey = ValueKey<String>(
  'merzox.pictureViewer.close',
);

/// Shows [url] full-screen. Does nothing when there is no picture to show.
Future<void> showPictureViewer(BuildContext context, String url) {
  if (url.trim().isEmpty) return Future<void>.value();

  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (BuildContext dialogContext) => _PictureViewer(url: url.trim()),
  );
}

class _PictureViewer extends StatelessWidget {
  final String url;

  const _PictureViewer({required this.url});

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      key: kPictureViewerKey,
      backgroundColor: Colors.transparent,
      child: Stack(
        children: <Widget>[
          // Anywhere off the picture closes it, which is what a reader who
          // opened it by pressing the picture expects to be able to do.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  // A picture that will not load leaves the reader looking at
                  // a black screen with no way to tell whether anything is
                  // coming, so it says so and keeps the way out.
                  errorBuilder: (_, _, _) => Icon(
                    Icons.broken_image_outlined,
                    size: 64,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                  loadingBuilder:
                      (
                        BuildContext _,
                        Widget child,
                        ImageChunkEvent? progress,
                      ) {
                        if (progress == null) return child;
                        return const CircularProgressIndicator(
                          color: Colors.white,
                        );
                      },
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: AlignmentDirectional.topStart,
              child: IconButton(
                key: kPictureViewerCloseKey,
                tooltip: 'common.close'.tr(),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
