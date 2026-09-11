import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/orders/widgets/order_text_prompt.dart';

import 'localization_test_harness.dart';

/// The box that asks for a cancellation reason or a new address.
///
/// All three callers used to dispose the field's controller the line after the
/// `await`, while the box was still fading out with the field alive - which
/// threw during the next build and put a framework assertion on the screen.
/// The controller belongs to the box now, so what is held here is that the box
/// can be answered and dismissed without anything being thrown after it.

/// Opens the box and hands back the list its answer will land in - the box is
/// still open when this returns, so there is nothing in it yet.
Future<List<String?>> _open(
  WidgetTester tester, {
  String initialText = '',
}) async {
  final List<String?> answers = <String?>[];

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                answers.add(
                  await askForOrderText(
                    context,
                    title: 'orders.cancelTitle'.tr(),
                    hint: 'orders.cancelReason'.tr(),
                    confirmLabel: 'common.confirm'.tr(),
                    initialText: initialText,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
      builder: (BuildContext context, Widget? child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await settleFrames(tester);

  return answers;
}

/// Runs the box's closing animation right out, which is when the fault used to
/// surface: the future is handed back the moment it is popped, not when it is
/// gone from the tree.
Future<void> _letItClose(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await settleFrames(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  testWidgets('it opens with the wording it was given', (tester) async {
    final List<String?> answers = await _open(tester);

    expect(find.text('orders.cancelTitle'.tr()), findsOneWidget);
    expect(find.text('orders.cancelReason'.tr()), findsOneWidget);
    expect(find.text('common.confirm'.tr()), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('orderPrompt.dismiss')));
    await _letItClose(tester);

    expect(answers, <String?>[null]);
  });

  testWidgets('it opens on the text it was handed', (tester) async {
    await _open(tester, initialText: 'رام الله ، المصيون');

    expect(find.text('رام الله ، المصيون'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('orderPrompt.dismiss')));
    await _letItClose(tester);
  });

  testWidgets('going through with it hands back the writing, trimmed', (
    tester,
  ) async {
    final List<String?> answers = await _open(tester);

    await tester.enterText(find.byType(TextField), '  غيرت رأيي  ');
    await tester.tap(find.byKey(const ValueKey<String>('orderPrompt.confirm')));
    await _letItClose(tester);

    expect(answers, <String?>['غيرت رأيي']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty answer is still an answer', (tester) async {
    // The callers tell "confirmed with nothing written" from "backed out" by
    // null against empty, so the two must not collapse into one.
    final List<String?> answers = await _open(tester);

    await tester.tap(find.byKey(const ValueKey<String>('orderPrompt.confirm')));
    await _letItClose(tester);

    expect(answers, <String?>['']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('backing out throws nothing as the box goes', (tester) async {
    // The fault itself: the controller used to be disposed here, while the box
    // was still on screen fading out with its field alive.
    final List<String?> answers = await _open(tester);

    await tester.enterText(find.byType(TextField), 'شيء ما');
    await tester.tap(find.byKey(const ValueKey<String>('orderPrompt.dismiss')));
    await _letItClose(tester);

    expect(tester.takeException(), isNull);
    expect(answers, <String?>[null]);
    expect(find.byType(TextField), findsNothing);
  });
}
