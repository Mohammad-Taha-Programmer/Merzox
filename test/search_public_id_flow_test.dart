import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/search/bloc/search_bloc.dart';
import 'package:merzox/features/search/bloc/search_event.dart';
import 'package:merzox/features/search/bloc/search_state.dart';
import 'package:merzox/features/search/pages/search_page.dart';
import 'package:merzox/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'localization_test_harness.dart';

SearchApiResponse _exactIdResponse() {
  return SearchApiResponse.fromJson(<String, dynamic>{
    'query': '54321',
    'businesses': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'business-54321',
        'publicId': '54321',
        'name': 'متجر صاحب المعرّف',
        'englishName': 'Identifier Store',
        'category': 'متاجر جديدة',
        'logoUrl': '',
        'products': <String>['المنتج الأول', 'المنتج الثاني'],
        'productCount': 2,
        'rating': 4.5,
        'ratingCount': 8,
        'followerCount': 3,
        'viewCount': 12,
        'colorValue': 0xffdeeef8,
        'address': 'رام الله',
      },
    ],
    'products': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'product-1',
        'name': 'المنتج الأول',
        'description': '',
        'price': 20,
        'discountPercent': 0,
        'finalPrice': 20,
        'inStock': true,
        'imageUrl': '',
        'imageUrls': <String>[],
        'classification': 'new',
        'rating': 4,
        'ratingCount': 2,
        'likeCount': 0,
        'isService': false,
        'hasVariants': false,
        'variants': <Map<String, dynamic>>[],
        'minPrice': 20,
        'maxPrice': 20,
        'minFinalPrice': 20,
        'maxFinalPrice': 20,
        'business': <String, dynamic>{
          'id': 'business-54321',
          'publicId': '54321',
          'name': 'متجر صاحب المعرّف',
          'category': 'متاجر جديدة',
          'logoUrl': '',
        },
      },
      <String, dynamic>{
        'id': 'product-2',
        'name': 'المنتج الثاني',
        'description': '',
        'price': 35,
        'discountPercent': 0,
        'finalPrice': 35,
        'inStock': true,
        'imageUrl': '',
        'imageUrls': <String>[],
        'classification': 'new',
        'rating': 5,
        'ratingCount': 3,
        'likeCount': 1,
        'isService': false,
        'hasVariants': false,
        'variants': <Map<String, dynamic>>[],
        'minPrice': 35,
        'maxPrice': 35,
        'minFinalPrice': 35,
        'maxFinalPrice': 35,
        'business': <String, dynamic>{
          'id': 'business-54321',
          'publicId': '54321',
          'name': 'متجر صاحب المعرّف',
          'category': 'متاجر جديدة',
          'logoUrl': '',
        },
      },
    ],
  });
}

final class _ExactPublicIdApi extends ApiService {
  final List<String> queries = <String>[];

  @override
  Future<SearchApiResponse> searchCatalog({
    required String query,
    int limit = 30,
  }) async {
    queries.add(query);
    return _exactIdResponse();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadAppTranslations);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'exact public ID survives API parsing and becomes a constrained bloc result',
    () async {
      final api = _ExactPublicIdApi();
      final bloc = SearchBloc(apiService: api);

      addTearDown(bloc.close);

      final resultFuture = bloc.stream.firstWhere(
        (SearchState state) => state.status == SearchStatus.success,
      );

      bloc.add(const SearchSubmitted(' 54321 '));

      final state = await resultFuture;

      expect(api.queries, <String>['54321']);
      expect(state.query, '54321');
      expect(state.hasExactBusinessMatch, isTrue);
      expect(state.businesses, hasLength(1));
      expect(state.businesses.single.publicId, '54321');
      expect(state.products, hasLength(2));

      expect(
        state.products.every((item) => item.business.publicId == '54321'),
        isTrue,
      );
    },
  );

  testWidgets(
    'exact public ID displays its business and products together in RTL',
    (WidgetTester tester) async {
      final api = _ExactPublicIdApi();
      final bloc = SearchBloc(apiService: api);

      addTearDown(bloc.close);

      final resultFuture = bloc.stream.firstWhere(
        (SearchState state) => state.status == SearchStatus.success,
      );

      bloc.add(const SearchSubmitted('54321'));

      await resultFuture;

      await pumpLocalized(
        tester,
        BlocProvider<SearchBloc>.value(value: bloc, child: const SearchPage()),
      );

      expect(
        find.byKey(const ValueKey<String>('exact-public-id-results-54321')),
        findsOneWidget,
      );

      expect(find.text('متجر صاحب المعرّف'), findsWidgets);

      expect(find.text('المنتج الأول'), findsWidgets);

      expect(find.text('المنتج الثاني'), findsWidgets);

      expect(find.text('متجر غير مرتبط'), findsNothing);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'exact ID results use readable full-width mobile cards without overflow',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(375, 812));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final api = _ExactPublicIdApi();
      final bloc = SearchBloc(apiService: api);
      addTearDown(bloc.close);

      final resultFuture = bloc.stream.firstWhere(
        (SearchState state) => state.status == SearchStatus.success,
      );
      bloc.add(const SearchSubmitted('54321'));
      await resultFuture;

      await pumpLocalized(
        tester,
        BlocProvider<SearchBloc>.value(value: bloc, child: const SearchPage()),
      );

      final exactResults = find.byKey(
        const ValueKey<String>('exact-public-id-results-54321'),
      );
      final businessCard = find.byKey(
        const ValueKey<String>('search-business-result-business-54321'),
      );
      final firstProductCard = find.byKey(
        const ValueKey<String>('search-product-result-product-1'),
      );

      expect(exactResults, findsOneWidget);
      expect(businessCard, findsOneWidget);
      expect(firstProductCard, findsOneWidget);
      expect(tester.getSize(businessCard).width, greaterThan(300));
      expect(tester.getSize(firstProductCard).width, greaterThan(300));
      expect(
        find.descendant(of: exactResults, matching: find.byType(GridView)),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('business-id-54321')),
        findsOneWidget,
      );
      expect(find.textContaining('متاجر جديدة'), findsOneWidget);
      expect(find.textContaining('رام الله'), findsOneWidget);
      expect(find.text('(8)'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey<String>(
            'search-business-product-count-business-54321',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('search-product-price-product-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('search-product-price-product-2')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the whole business and product cards dispatch their destination taps',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(375, 812));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final api = _ExactPublicIdApi();
      final bloc = SearchBloc(apiService: api);
      addTearDown(bloc.close);

      final resultFuture = bloc.stream.firstWhere(
        (SearchState state) => state.status == SearchStatus.success,
      );
      bloc.add(const SearchSubmitted('54321'));
      await resultFuture;

      SearchBusinessApiModel? openedBusiness;
      SearchProductApiModel? openedProduct;

      await pumpLocalized(
        tester,
        BlocProvider<SearchBloc>.value(
          value: bloc,
          child: SearchPage(
            onBusinessResultTap: (business) => openedBusiness = business,
            onProductResultTap: (product) => openedProduct = product,
          ),
        ),
      );

      final businessCard = find.byKey(
        const ValueKey<String>('search-business-result-business-54321'),
      );
      final productCard = find.byKey(
        const ValueKey<String>('search-product-result-product-1'),
      );

      await tester.tap(businessCard);
      await tester.pump();
      expect(openedBusiness?.id, 'business-54321');

      await tester.ensureVisible(productCard);
      await tester.tap(productCard);
      await tester.pump();
      expect(openedProduct?.product.id, 'product-1');
      expect(openedProduct?.business.id, 'business-54321');
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'a textual query with one business is not misclassified as an ID match',
    () {
      final response = _exactIdResponse();

      final state = SearchState(
        status: SearchStatus.success,
        query: 'صاحب المعرّف',
        products: response.products,
        businesses: response.businesses,
      );

      expect(state.hasExactBusinessMatch, isFalse);
    },
  );
}
