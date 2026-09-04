import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BusinessIdBadge extends StatelessWidget {
  final String id;
  final String dialogTitle;
  final String copyLabel;
  final String copiedMessage;
  final String closeLabel;
  final String tapHint;

  const BusinessIdBadge({
    required this.id,
    required this.dialogTitle,
    required this.copyLabel,
    required this.copiedMessage,
    required this.closeLabel,
    required this.tapHint,
    super.key,
  });

  Future<void> _copyAndClose({
    required BuildContext pageContext,
    required BuildContext dialogContext,
  }) async {
    await Clipboard.setData(ClipboardData(text: id));

    if (!dialogContext.mounted) {
      return;
    }

    Navigator.of(dialogContext).pop();

    if (!pageContext.mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(pageContext);

    if (messenger == null) {
      return;
    }

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(copiedMessage)));
  }

  Future<void> _showFullId(BuildContext pageContext) {
    return showDialog<void>(
      context: pageContext,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(dialogTitle, textAlign: TextAlign.start),
          content: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 220, maxWidth: 340),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: SelectableText(
                id,
                key: ValueKey<String>('business-id-full-$id'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF2B2B2B),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              key: ValueKey<String>('business-id-close-$id'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: Text(closeLabel),
            ),
            TextButton.icon(
              key: ValueKey<String>('business-id-copy-$id'),
              onPressed: () {
                unawaited(
                  _copyAndClose(
                    pageContext: pageContext,
                    dialogContext: dialogContext,
                  ),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: Text(copyLabel),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const borderRadius = BorderRadiusDirectional.only(
      topStart: Radius.circular(5),
      bottomStart: Radius.circular(5),
    );

    return Semantics(
      button: true,
      label: '$dialogTitle: $id',
      hint: tapHint,
      child: Tooltip(
        message: tapHint,
        child: Material(
          color: const Color(0xFFEFEFEF),
          borderRadius: borderRadius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey<String>('business-id-$id'),
            borderRadius: BorderRadius.circular(5),
            onTap: () {
              unawaited(_showFullId(context));
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  'ID: $id',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF2B2B2B),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
