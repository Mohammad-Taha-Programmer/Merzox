import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/constants/dates.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/features/business/shell/widgets/full_value_dialog.dart';
import 'package:merzox/features/business/shell/widgets/merchant_orders_table.dart';
import 'package:merzox/features/business/shell/widgets/order_status_presentation.dart';

import 'localization_test_harness.dart';

/// The merchant's latest-orders table.
///
/// Five columns on a phone means text gets cut off, and a cut-off customer
/// name is worse than blank: it looks like data and is not. The table answers
/// that - a clipped cell opens its full value, and the order number, the one
/// field a merchant retypes elsewhere, goes to the clipboard on a long press.
/// The price column carries the currency, which it did not: a bare `45` in a
/// column headed `السعر` is a number without a unit.

OwnerOrder _order({
  String publicId = '222321',
  String customer = 'ياسمين خالد',
  num total = 45,
  String status = 'pending',
}) => OwnerOrder.fromJson(<String, dynamic>{
  'id': 'o-$publicId',
  'publicId': publicId,
  'customerName': customer,
  'total': total,
  'status': status,
  'createdAt': '2022-02-15T09:00:00.000Z',
});

Future<void> _pumpTable(WidgetTester tester, List<OwnerOrder> orders) {
  return pumpLocalized(
    tester,
    Scaffold(body: MerchantOrdersTable(orders: orders)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  testWidgets('the price column carries the currency, not a bare number', (
    WidgetTester tester,
  ) async {
    await _pumpTable(tester, <OwnerOrder>[_order(total: 45)]);

    expect(find.text('45 ₪'), findsOneWidget);
    expect(
      find.text('45'),
      findsNothing,
      reason: 'a figure in a price column without its unit is not a price',
    );
  });

  testWidgets('a clipped value opens in full when it is tapped', (
    WidgetTester tester,
  ) async {
    const String longName = 'عبد الرحمن محمد عبد الله الأحمد الشريف';
    await _pumpTable(tester, <OwnerOrder>[_order(customer: longName)]);

    // Nothing is open until it is asked for.
    expect(
      find.byKey(const ValueKey<String>('merchantOrders.fullValue')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('merchantOrders.customer.222321')),
    );
    await tester.pumpAndSettle();

    final Finder full = find.byKey(
      const ValueKey<String>('merchantOrders.fullValue'),
    );
    expect(full, findsOneWidget);
    expect(tester.widget<Text>(full).data, longName);
  });

  testWidgets('the box takes itself away after three seconds', (
    WidgetTester tester,
  ) async {
    await _pumpTable(tester, <OwnerOrder>[_order()]);

    await tester.tap(
      find.byKey(const ValueKey<String>('merchantOrders.customer.222321')),
    );
    await tester.pumpAndSettle();

    final Finder full = find.byKey(
      const ValueKey<String>('merchantOrders.fullValue'),
    );

    // Still up a moment before its time.
    await tester.pump(merchantFullValueDuration - const Duration(seconds: 1));
    expect(full, findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // Gone, with nothing asked of the reader.
    expect(full, findsNothing);
  });

  testWidgets('it asks nothing of the reader: no heading, no button', (
    WidgetTester tester,
  ) async {
    await _pumpTable(tester, <OwnerOrder>[_order()]);

    await tester.tap(
      find.byKey(const ValueKey<String>('merchantOrders.customer.222321')),
    );
    await tester.pumpAndSettle();

    // A merchant who tapped a word to read it does not need to be told they
    // are looking at a word. The heading string is gone from the catalogue
    // too, so there is nothing left to accidentally show.
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(find.text('common.done'.tr()), findsNothing);

    await tester.pump(merchantFullValueDuration);
    await tester.pumpAndSettle();
  });

  testWidgets('a reader who is done can close it early', (
    WidgetTester tester,
  ) async {
    await _pumpTable(tester, <OwnerOrder>[_order()]);

    await tester.tap(
      find.byKey(const ValueKey<String>('merchantOrders.customer.222321')),
    );
    await tester.pumpAndSettle();

    // Outside the box.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('merchantOrders.fullValue')),
      findsNothing,
    );
  });

  testWidgets('the date opens in full as well', (WidgetTester tester) async {
    await _pumpTable(tester, <OwnerOrder>[_order()]);

    await tester.tap(find.text(merzoxDay(DateTime(2022, 2, 15))));
    await tester.pumpAndSettle();

    final Finder full = find.byKey(
      const ValueKey<String>('merchantOrders.fullValue'),
    );
    expect(full, findsOneWidget);
    expect(tester.widget<Text>(full).data, merzoxDay(DateTime(2022, 2, 15)));

    await tester.pump(merchantFullValueDuration);
    await tester.pumpAndSettle();
  });

  testWidgets('holding the order number copies it and says so', (
    WidgetTester tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _pumpTable(tester, <OwnerOrder>[_order(publicId: '232415')]);

    await tester.longPress(
      find.byKey(const ValueKey<String>('merchantOrders.number.232415')),
    );
    await tester.pumpAndSettle();

    // The hash is this screen's decoration, not part of the number, and a
    // merchant pasting it into a search box does not want it.
    expect(copied, '232415');
    expect(find.text('businessShell.orderNumberCopied'.tr()), findsOneWidget);
  });

  testWidgets('a cell with nothing worth copying does not copy its label', (
    WidgetTester tester,
  ) async {
    int copies = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') copies += 1;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _pumpTable(tester, <OwnerOrder>[_order(customer: 'ياسمين خالد')]);

    await tester.longPress(
      find.byKey(const ValueKey<String>('merchantOrders.customer.222321')),
    );
    await tester.pumpAndSettle();

    expect(copies, 0);
  });

  testWidgets('the status badge opens its full label too', (
    WidgetTester tester,
  ) async {
    // The badge is 58 wide and `تم التسليم` does not fit, so it is the value
    // in the row most often cut - and it was the one cell with no way back to
    // its full text.
    await _pumpTable(tester, <OwnerOrder>[_order(status: 'delivered')]);

    await tester.tap(find.byType(MerchantStatusBadge));
    await tester.pumpAndSettle();

    final Finder full = find.byKey(
      const ValueKey<String>('merchantOrders.fullValue'),
    );
    expect(full, findsOneWidget);
    expect(
      tester.widget<Text>(full).data,
      'merchantOrder.statuses.delivered'.tr(),
    );
  });

  testWidgets('the badge stands aside when the row opens the order', (
    WidgetTester tester,
  ) async {
    OwnerOrder? opened;

    await pumpLocalized(
      tester,
      Scaffold(
        body: MerchantOrdersTable(
          orders: <OwnerOrder>[_order(status: 'delivered')],
          onOpen: (OwnerOrder order) => opened = order,
        ),
      ),
    );

    await tester.tap(find.byType(MerchantStatusBadge));
    await tester.pumpAndSettle();

    expect(opened?.publicId, '222321');
    expect(
      find.byKey(const ValueKey<String>('merchantOrders.fullValue')),
      findsNothing,
    );
  });

  testWidgets('every row it is given is drawn', (WidgetTester tester) async {
    await _pumpTable(tester, <OwnerOrder>[
      for (int index = 0; index < 6; index++)
        _order(publicId: '22232$index', total: 10 + index),
    ]);

    expect(find.byType(MerchantOrderRow), findsNWidgets(6));
    expect(find.text('#222320'), findsOneWidget);
    expect(find.text('#222325'), findsOneWidget);
  });

  testWidgets('a row opens its order when the table is asked to', (
    WidgetTester tester,
  ) async {
    OwnerOrder? opened;

    await pumpLocalized(
      tester,
      Scaffold(
        body: MerchantOrdersTable(
          orders: <OwnerOrder>[_order()],
          onOpen: (OwnerOrder order) => opened = order,
        ),
      ),
    );

    await tester.tap(find.byType(MerchantOrderRow));
    await tester.pumpAndSettle();

    expect(opened?.publicId, '222321');
  });
}
