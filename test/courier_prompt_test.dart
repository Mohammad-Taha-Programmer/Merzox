import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/business/orders/courier_prompt.dart';

import 'localization_test_harness.dart';

/// Saving a courier used to put a red screen on the phone.
///
/// `'package:flutter/src/widgets/framework.dart': Failed assertion: line 6268
/// pos 12: '_dependents.isEmpty': is not true` - raised the instant the
/// merchant pressed save, and naming nothing about couriers or dialogs.
///
/// The cause was two lines the caller ran after the `await`: it built the
/// name and phone controllers itself and disposed them as soon as
/// `showDialog` returned. But `showDialog` returns when the route is popped,
/// not when the box is gone - the dialog is still on screen fading out, its
/// fields still mounted and still holding those controllers.
///
/// Which is why these tests do not stop at the pop. `pumpAndSettle` runs the
/// exit animation to its end, and that is the part that used to throw: a test
/// that only awaited the future would have passed over the fault.

const Duration _aFrame = Duration(milliseconds: 16);

Future<Future<CourierDetails?>> _open(
  WidgetTester tester, {
  String name = '',
  String phone = '',
}) async {
  late Future<CourierDetails?> answer;

  await pumpLocalized(
    tester,
    Builder(
      builder: (BuildContext context) => TextButton(
        onPressed: () {
          answer = askForCourier(
            context,
            initialName: name,
            initialPhone: phone,
          );
        },
        child: const Text('open'),
      ),
    ),
    textDirection: TextDirection.rtl,
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  return answer;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  testWidgets('saving hands back what was typed, and closes cleanly', (
    WidgetTester tester,
  ) async {
    final Future<CourierDetails?> answer = await _open(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('courierPrompt.name')),
      'أحمد',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('courierPrompt.phone')),
      ' 0599123456 ',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('courierPrompt.confirm')),
    );

    // The pop, and then the whole way out. The second part is the test.
    await tester.pump();
    await tester.pump(_aFrame);
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason: 'the box was still fading out when its fields were pulled apart',
    );

    final CourierDetails? courier = await answer;
    expect(courier?.name, 'أحمد');
    expect(courier?.phone, '0599123456', reason: 'trimmed, as it is stored');
  });

  testWidgets('backing out hands back nothing, and closes cleanly', (
    WidgetTester tester,
  ) async {
    final Future<CourierDetails?> answer = await _open(tester, name: 'سامي');

    await tester.tap(
      find.byKey(const ValueKey<String>('courierPrompt.dismiss')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(await answer, isNull);
  });

  testWidgets('it opens on the courier the order already has', (
    WidgetTester tester,
  ) async {
    await _open(tester, name: 'سامي', phone: '0591111111');

    expect(find.text('سامي'), findsOneWidget);
    expect(find.text('0591111111'), findsOneWidget);
  });

  testWidgets('a name left blank is refused by the caller, not by the box', (
    WidgetTester tester,
  ) async {
    // The box reports what was typed; whether an empty name is worth sending
    // is the order screen's decision, and it declines. Stated here so the two
    // halves of that rule stay together in one place a reader can find.
    final Future<CourierDetails?> answer = await _open(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('courierPrompt.confirm')),
    );
    await tester.pumpAndSettle();

    expect((await answer)?.name, isEmpty);
  });
}
