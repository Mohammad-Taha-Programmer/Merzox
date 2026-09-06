import 'package:flutter/material.dart';

/// A round picture that survives not arriving.
///
/// `CircleAvatar.backgroundImage` paints through a `DecorationImage`, and a
/// decoration has nowhere to put an error builder - so a logo whose host does
/// not resolve throws on every single paint, filling the console and leaving a
/// blank circle with no explanation. A shop that changed hosts, or a stale URL
/// left behind by a deleted shop, was enough to do it.
///
/// This paints the image itself, which means it can be told what to do when it
/// fails: fall back to [fallback], once, quietly.
class RemoteCircleAvatar extends StatefulWidget {
  final String url;

  /// Drawn when there is no picture, or when the picture will not load.
  final Widget fallback;

  final double radius;
  final Color backgroundColor;

  const RemoteCircleAvatar({
    required this.url,
    required this.fallback,
    required this.radius,
    required this.backgroundColor,
    super.key,
  });

  @override
  State<RemoteCircleAvatar> createState() => _RemoteCircleAvatarState();
}

class _RemoteCircleAvatarState extends State<RemoteCircleAvatar> {
  /// Set once the picture has failed, so the next paint does not try again and
  /// report the same failure for ever.
  bool _unloadable = false;

  @override
  void didUpdateWidget(RemoteCircleAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new URL deserves a fresh attempt: the old one failing says nothing
    // about this one.
    if (oldWidget.url != widget.url) _unloadable = false;
  }

  @override
  Widget build(BuildContext context) {
    final double size = widget.radius * 2;
    final bool showPicture = widget.url.isNotEmpty && !_unloadable;

    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: ColoredBox(
          color: widget.backgroundColor,
          child: showPicture
              ? Image.network(
                  widget.url,
                  key: const ValueKey<String>('merzox.remoteAvatar.image'),
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) {
                    // Rebuilding during a build is not allowed, so the
                    // fallback is armed for the next frame.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _unloadable = true);
                    });
                    return Center(child: widget.fallback);
                  },
                )
              : Center(child: widget.fallback),
        ),
      ),
    );
  }
}
