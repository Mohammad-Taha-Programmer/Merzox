import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/business/shell/merchant_browse_widgets.dart';
import 'package:merzox/features/business/shell/widgets/order_status_presentation.dart';

import 'localization_test_harness.dart';

/// The row of controls over the merchant's order list.
///
/// None of these had a test: they were built as shared widgets and used from
/// two screens, and nothing checked what either screen actually showed.

const List<String> _statuses = <String>[
  'pending',
  'preparing',
  'outForDelivery',
  'delivered',
  'cancelled',
];

const Key _checked = ValueKey<String>('merchantStatusFilter.checked');

Future<List<String?>> _pumpChip(WidgetTester tester, {String? selected}) async {
  final List<String?> chosen = <String?>[];

  await pumpLocalized(
    tester,
    Scaffold(
      body: Center(
        child: MerchantStatusFilterChip(
          selected: selected,
          options: _statuses,
          labelOf: merchantOrderStatusLabel,
          onSelected: chosen.add,
        ),
      ),
    ),
  );

  return chosen;
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byType(MerchantStatusFilterChip));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  group('the section row', () {
    testWidgets('heading and control sit at opposite ends', (
      WidgetTester tester,
    ) async {
      await pumpLocalized(
        tester,
        const Scaffold(
          body: MerchantSectionRow(
            heading: 'جميع الطلبات',
            trailing: SizedBox(
              key: ValueKey<String>('control'),
              width: 116,
              height: 34,
            ),
          ),
        ),
      );

      // Measured inside the row rather than around it: the widget carries a
      // gutter, and the claim is about where the two sit within it.
      final Rect row = tester.getRect(
        find.descendant(
          of: find.byType(MerchantSectionRow),
          matching: find.byType(Row),
        ),
      );
      final Rect heading = tester.getRect(find.text('جميع الطلبات'));
      final Rect control = tester.getRect(
        find.byKey(const ValueKey<String>('control')),
      );

      // Right-to-left: the heading takes the start edge and the control the
      // far one, with the gap between them being whatever is left over. The
      // heading used to be centred, so the two drifted with its length.
      expect(heading.right, closeTo(row.right, 1));
      expect(control.left, closeTo(row.left, 1));
      expect(heading.left, greaterThan(control.right));
    });

    testWidgets('a long heading is cut rather than shoving the control off', (
      WidgetTester tester,
    ) async {
      await pumpLocalized(
        tester,
        const Scaffold(
          body: MerchantSectionRow(
            heading:
                'عنوان طويل جداً لا ينتهي أبداً ويستمر في الامتداد بلا رحمة',
            trailing: SizedBox(
              key: ValueKey<String>('control'),
              width: 116,
              height: 34,
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(const ValueKey<String>('control'))).width,
        116,
      );
    });
  });

  group('the status filter', () {
    testWidgets('it reads "order status" until one is picked', (
      WidgetTester tester,
    ) async {
      await _pumpChip(tester);

      expect(find.text('businessShell.orderStatus'.tr()), findsOneWidget);
    });

    testWidgets('the menu offers every status', (WidgetTester tester) async {
      await _pumpChip(tester);
      await _openMenu(tester);

      for (final String status in _statuses) {
        expect(
          find.text(merchantOrderStatusLabel(status)),
          findsOneWidget,
          reason: '$status is not offered',
        );
      }
    });

    testWidgets('nothing is ticked while nothing is filtering', (
      WidgetTester tester,
    ) async {
      await _pumpChip(tester);
      await _openMenu(tester);

      expect(find.byKey(_checked), findsNothing);
    });

    testWidgets('the status in force is ticked, and only it', (
      WidgetTester tester,
    ) async {
      await _pumpChip(tester, selected: 'preparing');
      await _openMenu(tester);

      // Without this the menu read the same open as closed, so the way back to
      // every order was something a merchant had to be told rather than see.
      expect(find.byKey(_checked), findsOneWidget);

      final Rect tick = tester.getRect(find.byKey(_checked));
      final Rect label = tester.getRect(
        find.text(merchantOrderStatusLabel('preparing')).last,
      );
      expect(
        tick.center.dy,
        closeTo(label.center.dy, 2),
        reason: 'the tick belongs beside its own status, not another',
      );
    });

    testWidgets('picking a status reports it', (WidgetTester tester) async {
      final List<String?> chosen = await _pumpChip(tester);
      await _openMenu(tester);

      await tester.tap(find.text(merchantOrderStatusLabel('delivered')).last);
      await tester.pumpAndSettle();

      expect(chosen, <String?>['delivered']);
    });

    testWidgets('picking the one in force clears the filter', (
      WidgetTester tester,
    ) async {
      final List<String?> chosen = await _pumpChip(tester, selected: 'pending');
      await _openMenu(tester);

      await tester.tap(find.text(merchantOrderStatusLabel('pending')).last);
      await tester.pumpAndSettle();

      // Null is the whole list back, and it is the only way there.
      expect(chosen, <String?>[null]);
    });
  });

  group('the search field', () {
    testWidgets('its text is large enough to read', (
      WidgetTester tester,
    ) async {
      await pumpLocalized(
        tester,
        Scaffold(
          body: MerchantSearchRow(
            hint: 'ابحث برقم الطلب',
            onChanged: (_) {},
            onFilterPressed: () {},
          ),
        ),
      );

      final TextField field = tester.widget<TextField>(find.byType(TextField));

      // Ten was the artboard's figure and unreadable on a phone at arm's
      // length. The hint and what is typed must agree, or the field appears
      // to change size as soon as it is used.
      expect(field.style?.fontSize, greaterThanOrEqualTo(13));
      expect(field.decoration?.hintStyle?.fontSize, field.style?.fontSize);
    });
  });
}
