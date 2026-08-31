import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/features/business/shell/business_bloc.dart';
import 'package:merzox/features/business/shell/business_shell_page.dart';
import 'package:merzox/features/business/shell/merchant_product_images_page.dart';
import 'package:merzox/services/api_service.dart';

import 'auth_session_fixtures.dart';
import 'localization_test_harness.dart';

/// The overlay states of the merchant browse artboards, driven through the
/// widgets a merchant actually touches.
///
/// The bloc-level tests next door prove what each action sends. This file
/// proves the artboards' controls reach those actions at all: the `•••` menu
/// offers the right pair, the filter sheets return what was typed, and the
/// image screen hands back a reordered list.

Map<String, dynamic> _product(
  String id, {
  String name = 'أساس فت مي',
  bool isActive = true,
}) => <String, dynamic>{
  'id': id,
  'name': name,
  'description': 'وصف',
  'price': 35,
  'stockQuantity': 40,
  'unlimitedStock': false,
  'discountPercent': 0,
  'finalPrice': 35,
  'inStock': true,
  'keywords': const <String>[],
  'imageUrls': const <String>[],
  'classification': 'new',
  'isService': false,
  'isActive': isActive,
  'variants': const <Map<String, dynamic>>[],
};

class _ShellApi extends ApiService {
  List<OwnerProduct> stored = const <OwnerProduct>[];
  final List<Map<String, dynamic>> patched = <Map<String, dynamic>>[];

  @override
  Future<OwnerBusiness> ownerBusiness({required String token}) async =>
      OwnerBusiness.fromJson(const <String, dynamic>{
        'id': 'b1',
        'name': 'متجر',
      });

  @override
  Future<BusinessDashboardData> businessDashboard({
    required String token,
  }) async => BusinessDashboardData.fromJson(const <String, dynamic>{});

  @override
  Future<OwnerOrderList> ownerOrders({
    required String token,
    String statusGroup = '',
    MerchantOrderFilter filter = const MerchantOrderFilter(),
    int page = 1,
    int limit = 20,
  }) async => OwnerOrderList.fromJson(const <String, dynamic>{});

  @override
  Future<List<OwnerProduct>> ownerProducts({required String token}) async =>
      stored;

  @override
  Future<OwnerProduct> updateOwnerProduct({
    required String token,
    required String productId,
    required Map<String, dynamic> changes,
  }) async {
    patched.add(<String, dynamic>{'id': productId, ...changes});
    return OwnerProduct.fromJson(<String, dynamic>{
      ..._product(productId),
      ...changes,
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadAppTranslations);

  late _ShellApi api;

  setUp(() {
    api = _ShellApi();
    useAuthenticatedSession(business: true);
  });

  /// Pumps the merchant shell on its products tab.
  Future<BusinessBloc> pumpProducts(
    WidgetTester tester,
    List<Map<String, dynamic>> products,
  ) async {
    api.stored = products.map(OwnerProduct.fromJson).toList();

    final BusinessBloc bloc = BusinessBloc(apiService: api);
    addTearDown(bloc.close);

    final Future<BusinessState> ready = bloc.stream.firstWhere(
      (BusinessState state) => state.status == BusinessStatus.ready,
    );
    bloc.add(const BusinessStarted());
    await ready;
    bloc.add(const BusinessTabChanged(3));

    await pumpLocalized(
      tester,
      BlocProvider<BusinessBloc>.value(
        value: bloc,
        child: BusinessShellPage(onLoggedOut: () {}),
      ),
    );

    return bloc;
  }

  group('the product actions menu', () {
    testWidgets('a live product is offered hiding, not showing', (
      WidgetTester tester,
    ) async {
      await pumpProducts(tester, <Map<String, dynamic>>[_product('p1')]);

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await settleFrames(tester);

      expect(find.text('إخفاء المنتج عن المتجر'), findsOneWidget);
      expect(find.text('إظهار المنتج على المتجر'), findsNothing);
      expect(find.text('تكرار المنتج'), findsOneWidget);
      expect(find.text('حذف المنتج نهائيًا'), findsOneWidget);
    });

    testWidgets('a hidden product is offered showing instead', (
      WidgetTester tester,
    ) async {
      await pumpProducts(tester, <Map<String, dynamic>>[
        _product('p1', isActive: false),
      ]);

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await settleFrames(tester);

      expect(find.text('إظهار المنتج على المتجر'), findsOneWidget);
      expect(find.text('إخفاء المنتج عن المتجر'), findsNothing);
    });

    testWidgets('choosing hide sends the visibility change', (
      WidgetTester tester,
    ) async {
      await pumpProducts(tester, <Map<String, dynamic>>[_product('p1')]);

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await settleFrames(tester);
      await tester.tap(find.text('إخفاء المنتج عن المتجر'));
      await settleFrames(tester);

      expect(api.patched.single, <String, dynamic>{
        'id': 'p1',
        'isActive': false,
      });
    });

    testWidgets('deleting asks before it deletes', (WidgetTester tester) async {
      await pumpProducts(tester, <Map<String, dynamic>>[_product('p1')]);

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await settleFrames(tester);
      await tester.tap(find.text('حذف المنتج نهائيًا'));
      await settleFrames(tester);

      // Permanent deletion behind a single tap is what this dialog prevents.
      expect(find.text('هل تريد حذف المنتج نهائيًا؟'), findsOneWidget);
    });
  });

  group('the product filter sheet', () {
    testWidgets('the orange button raises it', (WidgetTester tester) async {
      await pumpProducts(tester, <Map<String, dynamic>>[_product('p1')]);

      await tester.tap(find.byIcon(Icons.tune_rounded));
      await settleFrames(tester);

      expect(find.text('تصفية'), findsOneWidget);
      expect(find.text('اسم المنتج'), findsOneWidget);
      expect(find.text('قم باختيار تصنيف المنتجات'), findsOneWidget);
      expect(find.text('قم باختيار حالة المنتج'), findsOneWidget);
    });

    testWidgets('searching by name narrows the list it returns to', (
      WidgetTester tester,
    ) async {
      await pumpProducts(tester, <Map<String, dynamic>>[
        _product('p1', name: 'أساس فت مي'),
        _product('p2', name: 'أحمر شفاه'),
      ]);
      expect(find.text('أحمر شفاه'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.tune_rounded));
      await settleFrames(tester);
      await tester.enterText(find.byType(TextField).first, 'شفاه');
      await tester.tap(find.text('بحث'));
      await settleFrames(tester);

      expect(find.text('أحمر شفاه'), findsOneWidget);
      expect(find.text('أساس فت مي'), findsNothing);
    });
  });

  group('the image screen', () {
    testWidgets('choosing an image makes it the first one saved', (
      WidgetTester tester,
    ) async {
      List<String>? saved;

      await pumpLocalized(
        tester,
        Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () async {
              saved = await Navigator.of(context).push<List<String>>(
                MaterialPageRoute<List<String>>(
                  builder: (_) => const MerchantProductImagesPage(
                    imageUrls: <String>[
                      'https://example.test/a.png',
                      'https://example.test/b.png',
                    ],
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settleFrames(tester);

      // The second image's own radio: the storefront leads with whichever
      // image is first, so choosing one has to reorder the list.
      await tester.tap(find.byType(InkResponse).last);
      await settleFrames(tester);
      await tester.tap(find.text('حفظ'));
      await settleFrames(tester);

      expect(saved, <String>[
        'https://example.test/b.png',
        'https://example.test/a.png',
      ]);
    });
  });
}
