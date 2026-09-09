import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/widgets/merzox_back_chevron.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/favorites/bloc/favorites_bloc.dart';
import 'package:merzox/features/favorites/bloc/favorites_event.dart';
import 'package:merzox/features/favorites/bloc/favorites_state.dart';
import 'package:merzox/features/favorites/pages/favorites_page.dart';
import 'package:merzox/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'golden/merzox_golden_harness.dart' as golden;
import 'localization_test_harness.dart';

/// What the two favourite cards show.
///
/// The shop card drew a generic glyph on a coloured tile and never asked for
/// the logo the list route has always served; the product card was checked at
/// the same time and did show its picture. Both are held here so neither can
/// quietly stop.

const String _logo = 'https://cdn.test/merzox/logo.png';
const String _picture = 'https://cdn.test/merzox/product.png';

Map<String, dynamic> _business({String logoUrl = _logo}) => <String, dynamic>{
  'id': '64b000000000000000000009',
  'publicId': '990011',
  'name': 'متجر الياسمين',
  'englishName': 'Alyasmeen',
  'category': 'beauty',
  'logoUrl': logoUrl,
  'products': const <String>[],
  'productCount': 1,
  'rating': 4,
  'ratingCount': 12,
  'followerCount': 3,
  'viewCount': 40,
  'discount': null,
  'colorValue': 0xffdeeef8,
  'address': 'رام الله ، المصيون',
};

Map<String, dynamic> _product({String imageUrl = _picture}) =>
    <String, dynamic>{
      'id': '64c000000000000000000101',
      'business': '64b000000000000000000009',
      'name': 'أساس فت مي',
      'description': '',
      'price': 35,
      'imageUrl': imageUrl,
      'imageUrls': <String>[if (imageUrl.isNotEmpty) imageUrl],
      'classification': 'new',
      'rating': 5,
      'ratingCount': 3,
      'discountPercent': 0,
      'finalPrice': 35,
      'inStock': true,
      'hasVariants': false,
      'variants': const <dynamic>[],
      // The contract refuses to default these. A product with no variants
      // still has complete price bounds - they collapse onto its one price -
      // because a missing bound would otherwise have to be inferred.
      'minPrice': 35,
      'maxPrice': 35,
      'minFinalPrice': 35,
      'maxFinalPrice': 35,
    };

class _FavoritesApi extends ApiService {
  final String logoUrl;
  final String imageUrl;

  _FavoritesApi({this.logoUrl = _logo, this.imageUrl = _picture});

  @override
  Future<FavoriteBusinessListApiResponse> favoriteBusinesses({
    required String token,
    int page = 1,
    int limit = 20,
  }) async => FavoriteBusinessListApiResponse.fromJson(<String, dynamic>{
    'businesses': <Map<String, dynamic>>[_business(logoUrl: logoUrl)],
    'pagination': <String, dynamic>{
      'page': 1,
      'limit': limit,
      'total': 1,
      'hasMore': false,
    },
  });

  @override
  Future<FavoriteProductListApiResponse> favoriteProducts({
    required String token,
    int page = 1,
    int limit = 20,
  }) async => FavoriteProductListApiResponse.fromJson(<String, dynamic>{
    'products': <Map<String, dynamic>>[
      <String, dynamic>{
        'business': _business(logoUrl: logoUrl),
        'product': _product(imageUrl: imageUrl),
      },
    ],
    'pagination': <String, dynamic>{
      'page': 1,
      'limit': limit,
      'total': 1,
      'hasMore': false,
    },
  });
}

Future<FavoritesBloc> _pumpFavorites(
  WidgetTester tester, {
  FavoritesTab tab = FavoritesTab.businesses,
  String logoUrl = _logo,
  String imageUrl = _picture,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    AuthBloc.sessionKey: true,
    AuthBloc.tokenKey: 'favorites-token',
    AuthBloc.userTypeKey: 'customer',
  });

  final FavoritesBloc bloc = FavoritesBloc(
    apiService: _FavoritesApi(logoUrl: logoUrl, imageUrl: imageUrl),
  );
  addTearDown(bloc.close);

  // Awaited before pumping, the way the seed goldens do it: the tab's own
  // fetch has to have landed or the grid is still empty when it is looked at.
  //
  // A failed load settles this too, and is then asserted on. Waiting only for
  // `ready` hangs the whole test instead of failing it when a fixture is
  // mis-shaped, and a test that hangs says nothing about what is wrong.
  final Future<FavoritesState> settled = bloc.stream.firstWhere(
    (FavoritesState state) =>
        state.selectedTab == tab &&
        (state.status == FavoritesStatus.failure ||
            (state.status == FavoritesStatus.ready &&
                (tab == FavoritesTab.products
                    ? state.productsLoaded
                    : state.businessesLoaded))),
  );
  bloc.add(const FavoritesStarted());
  if (tab != FavoritesTab.businesses) {
    bloc.add(FavoritesTabChanged(tab));
  }
  final FavoritesState state = await settled;
  expect(
    state.status,
    FavoritesStatus.ready,
    reason: 'the fixture did not load: ${state.errorMessage}',
  );

  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: golden.merzoxGoldenTheme(),
      home: BlocProvider<FavoritesBloc>.value(
        value: bloc,
        child: const FavoritesPage(),
      ),
      builder: (BuildContext context, Widget? child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
    ),
  );
  await settleFrames(tester);

  return bloc;
}

/// The network image never resolves in a test, so what is asserted is that the
/// widget was asked for at the right address - not that bytes arrived.
Finder _networkImage(String url) => find.byWidgetPredicate(
  (Widget widget) =>
      widget is Image &&
      widget.image is NetworkImage &&
      (widget.image as NetworkImage).url == url,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
    await golden.loadMerzoxGoldenFonts();
  });

  testWidgets('the way back is the artboard chevron, not a Material arrow', (
    tester,
  ) async {
    await _pumpFavorites(tester);

    expect(find.byType(MerzoxBackChevron), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('the way back leaves the screen', (tester) async {
    // It sits over the centred title, so this is as much about the press
    // landing as about the mark.
    final FavoritesBloc bloc = FavoritesBloc(apiService: _FavoritesApi());
    addTearDown(bloc.close);
    bloc.add(const FavoritesStarted());

    SharedPreferences.setMockInitialValues(<String, Object>{
      AuthBloc.sessionKey: true,
      AuthBloc.tokenKey: 'favorites-token',
      AuthBloc.userTypeKey: 'customer',
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: golden.merzoxGoldenTheme(),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => BlocProvider<FavoritesBloc>.value(
                      value: bloc,
                      child: const FavoritesPage(),
                    ),
                  ),
                ),
                child: const Text('elsewhere'),
              ),
            ),
          ),
        ),
        builder: (BuildContext context, Widget? child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );

    await tester.tap(find.text('elsewhere'));
    await settleFrames(tester);
    expect(find.byType(FavoritesPage), findsOneWidget);

    await tester.tap(find.byType(MerzoxBackChevron));
    await settleFrames(tester);

    expect(find.byType(FavoritesPage), findsNothing);
  });

  testWidgets('a favourite shop shows its own logo', (tester) async {
    await _pumpFavorites(tester);

    expect(_networkImage(_logo), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>(
          'favorite-business-logo-64b000000000000000000009',
        ),
      ),
      findsOneWidget,
    );
    // What is not asserted here is that the glyph is gone: a network image
    // always fails in a test, so its errorBuilder draws the fallback and both
    // are in the tree. That the request was made at all is the whole change.
  });

  testWidgets('the mark is contained, not cropped to the tile', (tester) async {
    // A wide wordmark filled to its box loses its own ends.
    await _pumpFavorites(tester);

    final Image logo = tester.widget<Image>(_networkImage(_logo));
    expect(logo.fit, BoxFit.contain);
  });

  testWidgets('a shop with no logo keeps the standing glyph', (tester) async {
    await _pumpFavorites(tester, logoUrl: '');

    expect(find.byIcon(Icons.storefront_outlined), findsOneWidget);
    expect(_networkImage(_logo), findsNothing);
  });

  testWidgets('a favourite product shows its picture', (tester) async {
    await _pumpFavorites(tester, tab: FavoritesTab.products);

    expect(_networkImage(_picture), findsOneWidget);
  });

  testWidgets('a product with no picture keeps the standing glyph', (
    tester,
  ) async {
    await _pumpFavorites(tester, tab: FavoritesTab.products, imageUrl: '');

    expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
  });
}
