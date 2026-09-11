import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/home/presentation/bloc/home_state_.dart';
import 'package:merzox/features/product_details/pages/product_details_page.dart';

import 'catalog_test_fixtures.dart';
import 'localization_test_harness.dart';

/// A shopkeeper looking at their own product.
///
/// It happens the moment a customer shares one into a conversation and the
/// shopkeeper taps the card. Ordering it would be their own order, in their
/// own shop, against their own stock - so the four controls that would start
/// one are frozen. For a customer, on either kind of account, they work as
/// they always did.
///
/// The controls are exercised on their own rather than through the page: the
/// product page never settles in a test, which is why the picture slider was
/// pulled out of it before this.

HomeBusiness _shop() => HomeBusiness(
  id: 'b1',
  publicId: '93872',
  name: 'البتول كوزماتيكس',
  englishName: 'Al Batoul',
  category: 'Cosmetics',
  logoUrl: '',
  description: '',
  address: 'أريحا',
  products: const <String>[],
  productCount: 1,
  rating: 0,
  ratingCount: 0,
  followerCount: 0,
  viewCount: 0,
  colorValue: 0xffdeeef8,
);

bool _live(WidgetTester tester, Finder finder) {
  final Widget widget = tester.widget(finder);

  if (widget is FilledButton) return widget.onPressed != null;
  if (widget is OutlinedButton) return widget.onPressed != null;
  if (widget is IconButton) return widget.onPressed != null;

  fail('not a button: $widget');
}

Finder _stepper(IconData icon) =>
    find.ancestor(of: find.byIcon(icon), matching: find.byType(IconButton));

Future<void> _pumpQuantity(WidgetTester tester, {required bool enabled}) {
  return pumpLocalized(
    tester,
    Scaffold(body: ProductQuantityRow(quantity: 1, enabled: enabled)),
  );
}

Future<void> _pumpActions(WidgetTester tester, {required bool enabled}) {
  return pumpLocalized(
    tester,
    Scaffold(
      body: ProductPurchaseActions(
        onAdd: () {},
        onBuy: () {},
        inStock: true,
        selectionRequired: false,
        enabled: enabled,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  group('the shop that sells it', () {
    testWidgets('cannot choose a quantity of its own stock', (
      WidgetTester tester,
    ) async {
      await _pumpQuantity(tester, enabled: false);

      // Frozen, not hidden: the page keeps its shape, so nothing moves under
      // a reader who tapped a card expecting a product page.
      expect(_stepper(Icons.add_rounded), findsOneWidget);
      expect(_stepper(Icons.remove_rounded), findsOneWidget);

      expect(_live(tester, _stepper(Icons.add_rounded)), isFalse);
      expect(_live(tester, _stepper(Icons.remove_rounded)), isFalse);
    });

    testWidgets('cannot order from itself', (WidgetTester tester) async {
      await _pumpActions(tester, enabled: false);

      expect(
        find.widgetWithText(FilledButton, 'أضف إلى السلة'),
        findsOneWidget,
      );
      expect(find.widgetWithText(OutlinedButton, 'شراء الآن'), findsOneWidget);

      expect(
        _live(tester, find.widgetWithText(FilledButton, 'أضف إلى السلة')),
        isFalse,
      );
      expect(
        _live(tester, find.widgetWithText(OutlinedButton, 'شراء الآن')),
        isFalse,
      );
    });
  });

  group('a customer', () {
    testWidgets('keeps the stepper', (WidgetTester tester) async {
      await _pumpQuantity(tester, enabled: true);

      expect(_live(tester, _stepper(Icons.add_rounded)), isTrue);
      expect(_live(tester, _stepper(Icons.remove_rounded)), isTrue);
    });

    testWidgets('keeps both ways to buy', (WidgetTester tester) async {
      await _pumpActions(tester, enabled: true);

      expect(
        _live(tester, find.widgetWithText(FilledButton, 'أضف إلى السلة')),
        isTrue,
      );
      expect(
        _live(tester, find.widgetWithText(OutlinedButton, 'شراء الآن')),
        isTrue,
      );
    });
  });

  group('what a page is by default', () {
    test('every existing route builds a customer page', () {
      // None of them passes the flag, and none of them may lose its buttons
      // to this.
      expect(
        ProductDetailsPage(
          business: _shop(),
          product: catalogProduct(id: 'p1'),
        ).viewerOwnsProduct,
        isFalse,
      );
    });

    testWidgets('and both controls answer unless told otherwise', (
      WidgetTester tester,
    ) async {
      await pumpLocalized(
        tester,
        Scaffold(
          body: Column(
            children: <Widget>[
              const ProductQuantityRow(quantity: 1),
              ProductPurchaseActions(
                onAdd: () {},
                onBuy: () {},
                inStock: true,
                selectionRequired: false,
              ),
            ],
          ),
        ),
      );

      expect(_live(tester, _stepper(Icons.add_rounded)), isTrue);
      expect(
        _live(tester, find.widgetWithText(FilledButton, 'أضف إلى السلة')),
        isTrue,
      );
    });
  });
}
