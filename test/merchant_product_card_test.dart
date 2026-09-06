import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/features/business/shell/merchant_browse_widgets.dart';

import 'golden/merzox_golden_harness.dart';

/// A product card on a phone whose owner turned the text up.
///
/// The reader's device reports `font_scale 1.3`, and at that size the card
/// overflowed its own height by three pixels and printed the stripe across the
/// screen. The goldens never saw it: they pin the scale to 1, which is the one
/// setting the fault does not appear at.
///
/// The fix is not to shrink the text back - that argues with a choice the
/// reader made deliberately, and usually for a reason. The card grows.

/// The artboard's height, which is now a floor rather than a ceiling.
const double _artboardHeight = 127;

OwnerProduct _product({
  String name = 'أحمر الشفاه',
  double price = 5,
  int stockQuantity = 6,
}) {
  return OwnerProduct(
    id: 'p1',
    name: name,
    description: '',
    price: price,
    stockQuantity: stockQuantity,
    unlimitedStock: false,
    classification: 'new',
    isActive: true,
    imageUrls: const <String>[],
  );
}

Future<void> _pumpCard(
  WidgetTester tester, {
  required double textScale,
  OwnerProduct? product,
}) async {
  await pumpMerzoxGoldenPage(
    tester,
    MediaQuery(
      data: MediaQueryData(
        size: merzoxGoldenSurfaceSize,
        devicePixelRatio: 1,
        padding: const EdgeInsets.only(top: 44),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: MerchantProductCard(
            product: product ?? _product(),
            onOpen: () {},
            onAction: (_) {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadMerzoxGoldenFonts();
    await loadMerzoxGoldenDateSymbols();
  });

  group('the card at the size the reader chose', () {
    testWidgets('at the default scale it is the height the board draws', (
      WidgetTester tester,
    ) async {
      await _pumpCard(tester, textScale: 1);

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(MerchantProductCard)).height,
        // The card carries a 16 gap under it, which is part of the widget.
        closeTo(_artboardHeight + 16, 0.5),
      );
    });

    testWidgets('turned up to the reader own 1.3 it does not overflow', (
      WidgetTester tester,
    ) async {
      await _pumpCard(tester, textScale: 1.3);

      // This is the stripe the reader photographed: three pixels over, on a
      // card whose height was fixed.
      expect(tester.takeException(), isNull);
    });

    testWidgets('it grows instead of clipping what it cannot fit', (
      WidgetTester tester,
    ) async {
      await _pumpCard(tester, textScale: 1);
      final double plain = tester
          .getSize(find.byType(MerchantProductCard))
          .height;

      await _pumpCard(tester, textScale: 1.3);
      final double enlarged = tester
          .getSize(find.byType(MerchantProductCard))
          .height;

      expect(enlarged, greaterThan(plain));
    });

    testWidgets('the largest setting Android offers still fits', (
      WidgetTester tester,
    ) async {
      // 2.0 is past what the system slider reaches, and past what the
      // accessibility settings reach either. If it holds here it holds.
      await _pumpCard(tester, textScale: 2);

      expect(tester.takeException(), isNull);
    });

    testWidgets('a long name is still cut rather than wrapped', (
      WidgetTester tester,
    ) async {
      await _pumpCard(
        tester,
        textScale: 1.3,
        product: _product(
          name: 'أحمر شفاه سائل مطفي طويل الثبات بدرجة الأحمر الكلاسيكي',
        ),
      );

      expect(tester.takeException(), isNull);
      // The card grows for the reader's font, not for a name that would push
      // it to three lines.
      expect(
        tester.widget<Text>(find.textContaining('أحمر شفاه سائل')).maxLines,
        1,
      );
    });
  }, skip: merzoxGoldenPlatformSkip);
}
