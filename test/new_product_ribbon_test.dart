import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/product_details/new_product_window.dart';
import 'package:merzox/features/product_details/pages/product_details_page.dart';
import 'package:merzox/features/product_details/widgets/new_product_ribbon.dart';
import 'package:merzox/services/api_service.dart';

import 'catalog_test_fixtures.dart';
import 'golden/merzox_golden_harness.dart';

/// The `جديد` flag on a product's photo.
///
/// It says something about the PRODUCT - that it went up this week - so it is
/// drawn over the slider rather than inside it. Paging to the second photo
/// must not carry it away, and the mark must take itself down after seven days
/// without anyone remembering to.
///
/// The shop already has a `الجديدة` shelf, but that is a shelf: a merchant
/// puts a product on it and it stays. This is age, and age expires.

Future<void> _pumpSlider(
  WidgetTester tester, {
  required List<String> images,
  required bool isNewlyAdded,
}) async {
  await pumpMerzoxGoldenPage(
    tester,
    withMerzoxGoldenDeviceInsets(
      Scaffold(
        backgroundColor: Colors.white,
        body: ProductImageSlider(
          images: images,
          selectedIndex: 0,
          isNewlyAdded: isNewlyAdded,
          onPageChanged: (_) {},
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

  group('when a product counts as new', () {
    final DateTime now = DateTime(2026, 9, 6, 12);

    test('one added today wears the mark', () {
      expect(
        productIsNewlyAdded(now.subtract(const Duration(hours: 2)), now: now),
        isTrue,
      );
    });

    test('it lasts the week the reader asked for', () {
      expect(kNewProductWindow, const Duration(days: 7));
      expect(
        productIsNewlyAdded(now.subtract(const Duration(days: 6)), now: now),
        isTrue,
      );
    });

    test('and takes itself down on the seventh day', () {
      // Nobody has to remember to remove it, which is the whole reason it is
      // age rather than the shelf the merchant chooses.
      expect(
        productIsNewlyAdded(now.subtract(const Duration(days: 7)), now: now),
        isFalse,
      );
      expect(
        productIsNewlyAdded(now.subtract(const Duration(days: 30)), now: now),
        isFalse,
      );
    });

    test('a product with no date is not new', () {
      // An older row, or a payload that dropped the field. Treating an unknown
      // age as new would pin the mark on for ever - the one thing a mark that
      // expires must never do.
      expect(productIsNewlyAdded(null, now: now), isFalse);
    });

    test('a clock that runs fast still reads as just added', () {
      expect(
        productIsNewlyAdded(now.add(const Duration(hours: 3)), now: now),
        isTrue,
      );
    });

    test('the date survives the wire', () {
      final BusinessProductApiModel parsed = BusinessProductApiModel.fromJson(
        <String, dynamic>{
          ...catalogProductJson(),
          'createdAt': '2026-09-06T09:00:00.000Z',
        },
      );

      expect(parsed.createdAt, DateTime.utc(2026, 9, 6, 9));
    });

    test('a payload without it parses rather than throwing', () {
      expect(
        BusinessProductApiModel.fromJson(catalogProductJson()).createdAt,
        isNull,
      );
    });
  });

  group('the shape the board draws', () {
    test('it is the tab from the artboard, not a rectangle', () {
      // 29.4 by 69.56, with the notch cut into the free end.
      expect(kNewRibbonWidth, 29.4);
      expect(kNewRibbonHeight, 69.56);
      expect(kNewRibbonNotchDepth, 19.35);
      expect(kNewRibbonNotchCentre, closeTo(kNewRibbonWidth / 2, 1));
    });

    test('the notch is a bite out of the tab, not most of it', () {
      expect(kNewRibbonNotchDepth, lessThan(kNewRibbonHeight / 2));
    });

    test('the tab stands where the board stands it', () {
      expect(kNewRibbonInset, 59.8);
    });
  });

  group('on the product screen', () {
    testWidgets('a product added this week wears it', (
      WidgetTester tester,
    ) async {
      await _pumpSlider(
        tester,
        images: <String>['https://cdn.test/a.jpg'],
        isNewlyAdded: true,
      );

      expect(find.byType(NewProductRibbon), findsOneWidget);
    });

    testWidgets('one added a month ago does not', (WidgetTester tester) async {
      await _pumpSlider(
        tester,
        images: <String>['https://cdn.test/a.jpg'],
        isNewlyAdded: false,
      );

      expect(find.byType(NewProductRibbon), findsNothing);
    });

    testWidgets('the flag is not inside the pager', (
      WidgetTester tester,
    ) async {
      await _pumpSlider(
        tester,
        images: <String>['https://cdn.test/a.jpg', 'https://cdn.test/b.jpg'],
        isNewlyAdded: true,
      );

      // If it were a page's child it would slide away with the photo - and
      // it belongs to the product, not to the picture showing.
      expect(
        find.descendant(
          of: find.byType(PageView),
          matching: find.byType(NewProductRibbon),
        ),
        findsNothing,
      );
      expect(find.byType(NewProductRibbon), findsOneWidget);
    });

    testWidgets('it stays put when the photo changes', (
      WidgetTester tester,
    ) async {
      await _pumpSlider(
        tester,
        images: <String>['https://cdn.test/a.jpg', 'https://cdn.test/b.jpg'],
        isNewlyAdded: true,
      );

      final Rect before = tester.getRect(find.byType(NewProductRibbon));

      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await settleMerzoxGoldenFrames(tester);

      expect(tester.getRect(find.byType(NewProductRibbon)), before);
    });
  }, skip: merzoxGoldenPlatformSkip);
}
