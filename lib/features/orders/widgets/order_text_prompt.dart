import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Asks for one line of writing and hands back what was written.
///
/// Returns `null` when the reader backed out, and the trimmed text - possibly
/// empty - when they went through with it.
///
/// It exists because of the shape it replaces. Every caller used to make a
/// `TextEditingController`, hand it to a `TextField` inside `showDialog`, and
/// dispose it on the line after the `await`. But `showDialog` returns the
/// moment the route is popped, not when it is gone: the box is still on screen
/// fading out, its field still mounted and still holding that controller. The
/// next frame rebuilt the dying box, `_AnimatedState.didUpdateWidget` called
/// `addListener` on a controller that no longer existed, and the build threw.
/// A build that throws leaves the subtree half-updated, so when the overlay
/// finally dropped the entry an inherited element still had dependents and the
/// framework raised `_dependents.isEmpty` - which is the red screen a reader
/// actually saw, several steps downstream of the cause.
///
/// The controller now belongs to the box itself, and goes when the box goes.
Future<String?> askForOrderText(
  BuildContext context, {
  required String title,
  required String hint,
  required String confirmLabel,
  String initialText = '',
  Color? confirmColor,
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) => _OrderTextPrompt(
      title: title,
      hint: hint,
      confirmLabel: confirmLabel,
      initialText: initialText,
      confirmColor: confirmColor,
    ),
  );
}

class _OrderTextPrompt extends StatefulWidget {
  final String title;
  final String hint;
  final String confirmLabel;
  final String initialText;
  final Color? confirmColor;

  const _OrderTextPrompt({
    required this.title,
    required this.hint,
    required this.confirmLabel,
    required this.initialText,
    required this.confirmColor,
  });

  @override
  State<_OrderTextPrompt> createState() => _OrderTextPromptState();
}

class _OrderTextPromptState extends State<_OrderTextPrompt> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey<String>('orderPrompt.field'),
        controller: _controller,
        maxLength: 250,
        maxLines: 3,
        decoration: InputDecoration(
          hintText: widget.hint,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const ValueKey<String>('orderPrompt.dismiss'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          key: const ValueKey<String>('orderPrompt.confirm'),
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          style: widget.confirmColor == null
              ? null
              : FilledButton.styleFrom(backgroundColor: widget.confirmColor),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
