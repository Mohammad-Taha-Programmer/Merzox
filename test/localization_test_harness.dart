// The `EasyLocalization` widget loads its catalogue through real asset I/O,
// which does not run on the faked clock inside `testWidgets`. Priming the
// singleton directly is the only deterministic way to render translated text in
// a widget test, and it needs the two implementation libraries below.
// ignore_for_file: implementation_imports

import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the real `assets/translations` catalogue into the translation
/// singleton that `.tr()` reads.
///
/// Call once from `setUpAll`. Using the shipped JSON rather than a fixture is
/// deliberate: a widget test then fails when a key is missing from the app's
/// own catalogue, not merely when it is missing from the test's copy.
Future<void> loadAppTranslations({String languageCode = 'ar'}) async {
  final raw = await File(
    'assets/translations/$languageCode.json',
  ).readAsString();

  Localization.load(
    Locale(languageCode),
    translations: Translations(jsonDecode(raw) as Map<String, dynamic>),
  );
}

/// Pumps [child] with translations resolved and the app's own text direction.
Future<void> pumpLocalized(
  WidgetTester tester,
  Widget child, {
  TextDirection textDirection = TextDirection.rtl,
}) async {
  // A tall surface so the whole page is laid out at once. The default 800x600
  // viewport pushes the product grid past the bottom edge, where a tap silently
  // misses and a "nothing happened" assertion would pass for the wrong reason.
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(textDirection: textDirection, child: child),
    ),
  );
  await settleFrames(tester);
}

/// A bounded settle.
///
/// `pumpAndSettle` waits for the frame scheduler to go idle, which these
/// screens never do, so a fixed number of frames is used instead. Twelve frames
/// is well past every animation on these pages.
Future<void> settleFrames(
  WidgetTester tester, {
  int frames = 12,
  Duration step = const Duration(milliseconds: 100),
}) async {
  for (var frame = 0; frame < frames; frame++) {
    await tester.pump(step);
  }
}

/// Every string currently rendered anywhere in the tree.
///
/// Used by the private-field tests: asserting on the whole rendered text set is
/// stronger than looking for one label, because a value leaking through an
/// unexpected widget is still caught.
Set<String> renderedText(WidgetTester tester) {
  final texts = <String>{};

  for (final widget in tester.allWidgets) {
    if (widget is Text) {
      final data = widget.data ?? widget.textSpan?.toPlainText();
      if (data != null) texts.add(data);
    } else if (widget is EditableText) {
      texts.add(widget.controller.text);
    }
  }

  return texts;
}
