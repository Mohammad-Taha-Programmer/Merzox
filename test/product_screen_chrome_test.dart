import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/core/widgets/merzox_back_chevron.dart';
import 'package:merzox/core/widgets/merzox_expandable_text.dart';
import 'package:merzox/core/widgets/merzox_icons.dart';
import 'package:merzox/features/home/presentation/bloc/home_state_.dart';
import 'package:merzox/features/product_details/bloc/product_details_bloc.dart';
import 'package:merzox/features/product_details/bloc/product_details_event.dart';
import 'package:merzox/features/product_details/bloc/product_details_state.dart';
import 'package:merzox/features/product_details/pages/product_details_page.dart';
import 'package:merzox/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_test_fixtures.dart';
import 'localization_test_harness.dart';

/// What a product's page draws around the product.
///
/// The two controls floating over the photographs were bare marks on whatever
/// the merchant happened to photograph, and one of them was Material's
/// `chevron_right_rounded` - which Material mirrors in an Arabic page, so the
/// way back pointed away from it. And every line on the page that could be
/// long was cut with no way to read the rest.
const String _businessId = '64b000000000000000000001';

const String _longName =
    'طقم أواني طهي ستانلس ستيل مقاوم للخدش والحرارة العالية 12 قطعة بمقابض '
    'سيليكون معزولة';

const String _longAddress =
    'فلسطين، محافظة رام الله والبيرة، مدينة البيرة، حي الشرفة، شارع القدس '
    'الرئيسي، عمارة النور، الطابق الثالث، مقابل مسجد عمر';

class _ProductApi extends ApiService {
  final BusinessProductApiModel product;

  _ProductApi(this.product);

  @override
  Future<BusinessProductApiModel> businessProduct({
    required String businessId,
    required String productId,
  }) async => product;

  @override
  Future<List<BusinessReviewApiModel>> productReviews({
    required String businessId,
    required String productId,
  }) async => const <BusinessReviewApiModel>[];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pumpProduct(
    WidgetTester tester, {
    String name = 'أساس فت مي',
    String description = 'وصف قصير.',
    String businessName = 'متجر الياسمين',
    String address = 'رام الله',
  }) async {
    final BusinessProductApiModel product = catalogProduct(
      name: name,
      description: description,
    );
    final ProductDetailsBloc bloc = ProductDetailsBloc(
      apiService: _ProductApi(product),
    );
    // Not awaited: `close` does not complete once the page has been pumped,
    // and awaiting it in teardown hangs the whole file.
    addTearDown(() => unawaited(bloc.close()));

    final Future<ProductDetailsState> ready = bloc.stream.firstWhere(
      (ProductDetailsState state) =>
          state.detailsStatus == ProductDetailsSectionStatus.ready,
    );
    bloc.add(
      ProductDetailsStarted(businessId: _businessId, initialProduct: product),
    );
    await ready;

    await pumpLocalized(
      tester,
      ProductDetailsPage(
        business: HomeBusiness(
          id: _businessId,
          name: businessName,
          category: 'مستحضرات تجميل',
          address: address,
          products: const <String>[],
          rating: 0,
          colorValue: 0xffdeeef8,
        ),
        product: product,
        bloc: bloc,
      ),
    );
  }

  group('the two controls over the photographs', () {
    testWidgets('the way back is the app\'s own mark', (
      WidgetTester tester,
    ) async {
      await pumpProduct(tester);

      expect(find.byType(MerzoxBackChevron), findsOneWidget);
      // And not the one that pointed the wrong way.
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    });

    testWidgets('it points the way back in Arabic', (
      WidgetTester tester,
    ) async {
      await pumpProduct(tester);

      final MerzoxBackChevronPainter painter =
          tester
                  .widget<CustomPaint>(
                    find.descendant(
                      of: find.byType(MerzoxBackChevron),
                      matching: find.byType(CustomPaint),
                    ),
                  )
                  .painter!
              as MerzoxBackChevronPainter;

      // Right, because right is where an Arabic reader came from.
      expect(painter.rightward, isTrue);
    });

    testWidgets('the share mark is the designer\'s, not Material\'s', (
      WidgetTester tester,
    ) async {
      await pumpProduct(tester);

      expect(find.byIcon(MerzoxIcons.productDetailsShare), findsOneWidget);
      expect(find.byIcon(Icons.share_outlined), findsNothing);
    });

    testWidgets('both sit on a disc that says where they are', (
      WidgetTester tester,
    ) async {
      // They had no edge at all before, so on a dark photograph they were
      // invisible and their tap targets were guesswork.
      await pumpProduct(tester);

      for (final String name in <String>['back', 'share']) {
        final Finder disc = find.byKey(
          ValueKey<String>('productDetails.$name'),
        );
        expect(disc, findsOneWidget);

        final Material material = tester.widget<Material>(
          find.descendant(of: disc, matching: find.byType(Material)).first,
        );
        expect(material.shape, isA<CircleBorder>());
        expect(material.color, kProductChromeCircleColour);
        // Half strength, so the photograph still reads through it.
        expect(material.color!.a, closeTo(0.5, 0.01));
      }
    });
  });

  group('a line too long for its place', () {
    testWidgets('the product name is cut, and opens when pressed', (
      WidgetTester tester,
    ) async {
      await pumpProduct(tester, name: _longName);

      final Finder name = find.byKey(
        const ValueKey<String>('productDetails.productName'),
      );
      expect(tester.widget<Text>(name).maxLines, 1);

      await tester.tap(name);
      await tester.pump();

      expect(tester.widget<Text>(name).maxLines, isNull);
      expect(tester.widget<Text>(name).overflow, TextOverflow.clip);

      // And closes again, because a page that grew by six lines should be
      // able to go back to the shape it had.
      await tester.tap(name);
      await tester.pump();
      expect(tester.widget<Text>(name).maxLines, 1);
    });

    testWidgets('a name that fits is left alone', (WidgetTester tester) async {
      await pumpProduct(tester);

      final Finder name = find.byKey(
        const ValueKey<String>('productDetails.productName'),
      );

      await tester.tap(name);
      await tester.pump();

      // Nothing to reveal, so nothing happens - rather than a line that
      // silently redraws itself identically.
      expect(tester.widget<Text>(name).maxLines, 1);
    });

    testWidgets('the seller\'s address is cut, and opens when pressed', (
      WidgetTester tester,
    ) async {
      // Long enough to overflow two lines at the width the harness gives the
      // page, which is wider than any phone.
      await pumpProduct(tester, address: '$_longAddress $_longAddress');

      final Finder line = find.byKey(
        const Key('merzox.productDetails.sellerAddress'),
      );
      expect(tester.widget<Text>(line).maxLines, 2);

      await tester.tap(line);
      await tester.pump();

      expect(tester.widget<Text>(line).maxLines, isNull);
    });

    testWidgets('a long seller name reads before it travels', (
      WidgetTester tester,
    ) async {
      // The name is also the way into the shop. When it fits, a press goes
      // there as it always did; when it does not, a press reads it, and the
      // logo beside it is still the way in.
      await pumpProduct(tester, businessName: _longName);

      final Finder line = find.byKey(
        const Key('merzox.productDetails.sellerName'),
      );

      await tester.tap(line);
      await tester.pump();

      expect(tester.widget<Text>(line).maxLines, isNull);
    });

    testWidgets('the description is four lines until it is asked for', (
      WidgetTester tester,
    ) async {
      await pumpProduct(
        tester,
        description: List<String>.filled(8, _longAddress).join(' '),
      );

      final Finder line = find.byKey(
        const ValueKey<String>('productDetails.description'),
      );
      expect(tester.widget<Text>(line).maxLines, 4);

      await tester.tap(line);
      await tester.pump();

      expect(tester.widget<Text>(line).maxLines, isNull);
    });

    testWidgets('every one of them is the same widget', (
      WidgetTester tester,
    ) async {
      // Four places, one rule. They were four `Text`s with four different
      // answers to what happens when the words do not fit.
      await pumpProduct(tester);

      expect(find.byType(MerzoxExpandableText), findsNWidgets(4));
    });
  });

  group('the quantity field', () {
    testWidgets('is one rounded field with a card in the middle', (
      WidgetTester tester,
    ) async {
      await pumpProduct(tester);

      final Container pill = tester.widget<Container>(
        find
            .ancestor(
              of: find.byIcon(Icons.remove_rounded),
              matching: find.byType(Container),
            )
            .last,
      );
      final BoxDecoration decoration = pill.decoration! as BoxDecoration;

      expect(decoration.color, MerzoxColors.kColor3D5A80);
      expect(
        decoration.borderRadius,
        BorderRadius.circular(kQuantityPillHeight / 2),
        reason: 'the ends of the field are meant to be round',
      );
    });
  });
}
