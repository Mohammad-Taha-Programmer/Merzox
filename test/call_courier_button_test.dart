import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/business/contact/store_contact_channels.dart';
import 'package:merzox/features/orders/pages/order_tracking_page.dart';

import 'localization_test_harness.dart';

/// What the call button on a courier card hands the phone.
///
/// The card used to print eleven digits and leave the reader to copy them into
/// their own dialler while a delivery was on its way. It carries a button now,
/// and the number travels with the tap.
///
/// The promise has two halves and both are checked here rather than assumed.
/// The digits handed over are the ones a phone can dial, not the ones a person
/// wrote down. And the address is a `tel:`, which opens the dialler with the
/// number in the field and waits - the last press belongs to the reader. A
/// button that rang somebody the moment it was brushed would be a different
/// and worse promise, so what goes over the channel is read rather than
/// trusted.

const MethodChannel _launcher = MethodChannel(
  'plugins.flutter.io/url_launcher',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  test('a number written for people becomes one a phone can dial', () {
    expect(telUri('0592029316')?.toString(), 'tel:0592029316');
    expect(
      telUri(' 059-202 9316 ')?.toString(),
      'tel:0592029316',
      reason: 'a dialler takes the number, not the way it was written down',
    );
  });

  test('a courier saved without a number offers no button', () {
    // The card asks `telUri` and draws nothing when it answers null, so such
    // an order shows a name and stops rather than a button that dials air.
    expect(telUri(''), isNull);
    expect(telUri('   '), isNull);
    expect(telUri('---'), isNull);
  });

  testWidgets('tapping it opens the dialler on that number', (
    WidgetTester tester,
  ) async {
    final List<MethodCall> sent = <MethodCall>[];

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_launcher, (
      MethodCall call,
    ) async {
      sent.add(call);
      return true;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _launcher,
        null,
      ),
    );

    await pumpLocalized(
      tester,
      Center(
        child: CourierCallButton(
          dial: telUri('059-202 9316')!,
          number: '059-202 9316',
        ),
      ),
      textDirection: TextDirection.rtl,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('tracking.callCourier')),
    );
    await tester.pumpAndSettle();

    expect(sent, hasLength(1), reason: 'one tap, one request to the phone');
    expect(sent.single.method, 'launch');

    final Map<Object?, Object?> arguments =
        sent.single.arguments as Map<Object?, Object?>;

    expect(
      arguments['url'],
      'tel:0592029316',
      reason: 'the dashes and spaces are not part of the number',
    );
  });

  testWidgets('it says the number out loud, for a reader who cannot see it', (
    WidgetTester tester,
  ) async {
    // The mark carries the meaning for everyone who can see it; a screen
    // reader is told which courier it is about to ring.
    await pumpLocalized(
      tester,
      Center(
        child: CourierCallButton(
          dial: telUri('0592029316')!,
          number: '0592029316',
        ),
      ),
      textDirection: TextDirection.rtl,
    );

    expect(
      find.bySemanticsLabel(RegExp('0592029316')),
      findsOneWidget,
      reason: 'a button labelled only "button" names nothing',
    );
  });
}
