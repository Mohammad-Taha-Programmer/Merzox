import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/constants/money.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/features/business/orders/merchant_order_detail_page.dart';

import 'golden/merzox_golden_harness.dart';
import 'localization_test_harness.dart';

/// The one order a merchant has opened.
///
/// Two things were wrong with it and neither was visible from the source. The
/// summary lines were aligned to `end`, which right-to-left means the left, so
/// they drifted inward against the status control and left a gap along the
/// edge they were meant to start from. And every figure on the screen was a
/// bare number: `35` under `السعر`, `45` under `المجموع الكلي` - amounts with
/// no unit, on a screen whose whole subject is money.

OwnerOrder _order() => OwnerOrder.fromJson(<String, dynamic>{
  'id': '64d000000000000000000201',
  'publicId': '222321',
  'customerName': 'ياسمين خالد',
  'customerPhone': '0592029316',
  'items': <Map<String, dynamic>>[
    <String, dynamic>{
      'productId': '64c000000000000000000201',
      'variantId': null,
      'name': 'أساس فت مي',
      'imageUrl': '',
      'unitPrice': 35,
      'quantity': 1,
      'variant': '',
    },
  ],
  'subtotal': 35,
  'deliveryFee': 10,
  'total': 45,
  'currency': 'ILS',
  'deliveryAddress': 'أريحا ، النبي موسى',
  'paymentMethod': 'cash',
  'status': 'pending',
  'statusGroup': 'current',
  'statusHistory': const <Map<String, dynamic>>[],
  'cancellationReason': '',
  'createdAt': '2022-02-15T10:00:00.000',
  'courier': const <String, dynamic>{},
});

/// Pumped through the golden harness, at the width the screen is drawn for.
///
/// Not the plain localisation harness: that one loads no fonts, so Flutter
/// falls back to a test face whose glyphs are all the same wide box. Arabic
/// laid out in it is far wider than the real thing and rows overflow that do
/// not overflow on a phone - which would make every measurement below a
/// measurement of the wrong text.
Future<void> _pumpDetail(WidgetTester tester) async {
  await pumpMerzoxGoldenPage(
    tester,
    withMerzoxGoldenDeviceInsets(
      MerchantOrderDetailPage(
        order: _order(),
        businessName: 'متجر الياسمين',
        businessAddress: 'رام الله',
        onStatusSelected: (_) {},
        onNotifyCustomer: () {},
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
    await loadMerzoxGoldenFonts();
  });

  testWidgets('the header is two columns at opposite edges', (
    WidgetTester tester,
  ) async {
    await _pumpDetail(tester);

    final Rect number = tester.getRect(find.textContaining('222321'));
    final Rect status = tester.getRect(find.text('حالة الطلب'));
    final Rect customer = tester.getRect(
      find.textContaining('اسم العميل').first,
    );

    // Right-to-left: the summary column starts at the right edge, the status
    // column ends at the left, and nothing of one crosses into the other.
    expect(
      number.right,
      closeTo(customer.right, 1),
      reason: 'the summary lines must share one starting edge',
    );
    expect(
      status.right,
      lessThan(number.left),
      reason: 'the status column must not run into the summary',
    );
  });

  testWidgets('the summary starts at the edge, not adrift of it', (
    WidgetTester tester,
  ) async {
    await _pumpDetail(tester);

    final Rect page = tester.getRect(find.byKey(merzoxGoldenRootKey));
    final Rect number = tester.getRect(find.textContaining('222321'));

    // The lines used to float a hundred pixels short of the edge because
    // `end` was read as the wrong side.
    expect(page.right - number.right, lessThan(40));
  });

  testWidgets('every figure in the products section carries its currency', (
    WidgetTester tester,
  ) async {
    await _pumpDetail(tester);

    // Price, delivery, and the line total.
    expect(find.text(merzoxPrice(35)), findsWidgets);
    expect(find.text(merzoxPrice(10)), findsWidgets);
    expect(find.text(merzoxPrice(45)), findsWidgets);

    // The quantity is a count, not money, and must not have been given a sign.
    expect(find.text('1'), findsWidgets);
    expect(find.text(merzoxPrice(1)), findsNothing);
  });

  testWidgets('every figure in the invoice carries its currency', (
    WidgetTester tester,
  ) async {
    await _pumpDetail(tester);

    for (final num amount in <num>[35, 10, 45]) {
      expect(
        find.text(merzoxPrice(amount)),
        findsWidgets,
        reason: '$amount is written without its currency',
      );
    }

    // A bare figure under a heading about money is a number without a unit.
    for (final String bare in <String>['35', '10', '45']) {
      expect(
        find.text(bare),
        findsNothing,
        reason: '$bare appears somewhere with no currency beside it',
      );
    }
  });
}
