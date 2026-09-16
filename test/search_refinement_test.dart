import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/widgets/merzox_back_chevron.dart';
import 'package:merzox/core/widgets/merzox_icons.dart';
import 'package:merzox/features/search/bloc/search_bloc.dart';
import 'package:merzox/features/search/bloc/search_event.dart';
import 'package:merzox/features/search/bloc/search_refinement.dart';
import 'package:merzox/features/search/bloc/search_state.dart';
import 'package:merzox/features/search/pages/search_page.dart';
import 'package:merzox/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'localization_test_harness.dart';

/// What the search screen asks the server, and what the reader can ask it.
///
/// One box had one answer - somewhere in this text - which is right until two
/// shops share a name, and until the thing being looked for is the goods
/// rather than the shop. These are the two questions that were added, read
/// where they matter: in the call that leaves the app.
class _RecordingSearchApi extends ApiService {
  final List<Map<String, Object?>> calls = <Map<String, Object?>>[];

  @override
  Future<SearchApiResponse> searchCatalog({
    required String query,
    String match = 'contains',
    String product = '',
    String productMatch = 'contains',
    int limit = 30,
  }) async {
    calls.add(<String, Object?>{
      'query': query,
      'match': match,
      'product': product,
      'productMatch': productMatch,
    });

    return const SearchApiResponse(
      query: '',
      products: <SearchProductApiModel>[],
      businesses: <SearchBusinessApiModel>[],
    );
  }
}

Future<SearchBloc> _pumpSearch(
  WidgetTester tester,
  _RecordingSearchApi api,
) async {
  final SearchBloc bloc = SearchBloc(apiService: api);
  addTearDown(bloc.close);
  bloc.add(const SearchStarted());

  await pumpLocalized(
    tester,
    BlocProvider<SearchBloc>.value(value: bloc, child: const SearchPage()),
  );

  return bloc;
}

/// The last thing the app asked the server.
Map<String, Object?> _lastCall(_RecordingSearchApi api) {
  expect(api.calls, isNotEmpty, reason: 'the app asked the server nothing');
  return api.calls.last;
}

Finder _chip(String label) => find.widgetWithText(InkWell, label);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadAppTranslations();
  });

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  // Reachable from the first frame. They were put behind "once a shop name is
  // typed", which left the goods box - half the search - sitting behind the
  // other half, and a reader who knows what they want to buy and not where
  // could never get to it.
  testWidgets('both questions are there before anything is typed', (
    tester,
  ) async {
    await _pumpSearch(tester, _RecordingSearchApi());

    expect(
      find.byKey(const ValueKey<String>('search.shopMatch')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('search.productField')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('search.productMatch')),
      findsOneWidget,
    );
  });

  testWidgets('a plain search still asks the plain question', (tester) async {
    final _RecordingSearchApi api = _RecordingSearchApi();
    await _pumpSearch(tester, api);

    await tester.enterText(find.byType(TextField).first, 'ابو خالد');
    await settleFrames(tester, frames: 30);

    expect(_lastCall(api), <String, Object?>{
      'query': 'ابو خالد',
      'match': 'contains',
      'product': '',
      'productMatch': 'contains',
    });
  });

  testWidgets('choosing where the name sits is asked at once', (tester) async {
    final _RecordingSearchApi api = _RecordingSearchApi();
    await _pumpSearch(tester, api);

    await tester.enterText(find.byType(TextField).first, 'ابو خالد');
    await settleFrames(tester, frames: 30);

    await tester.tap(_chip('يبدأ بـ').first);
    await settleFrames(tester);

    expect(_lastCall(api)['match'], 'starts');
  });

  testWidgets('the goods are a second condition, sent with the first', (
    tester,
  ) async {
    final _RecordingSearchApi api = _RecordingSearchApi();
    await _pumpSearch(tester, api);

    await tester.enterText(find.byType(TextField).first, 'ابو خالد');
    await settleFrames(tester, frames: 30);

    await tester.enterText(
      find.byKey(const ValueKey<String>('search.productField')),
      'جاكيت',
    );
    await settleFrames(tester, frames: 30);

    expect(_lastCall(api), <String, Object?>{
      'query': 'ابو خالد',
      'match': 'contains',
      'product': 'جاكيت',
      'productMatch': 'contains',
    });
  });

  testWidgets('similar is offered for the goods and for nothing else', (
    tester,
  ) async {
    final _RecordingSearchApi api = _RecordingSearchApi();
    await _pumpSearch(tester, api);

    await tester.enterText(find.byType(TextField).first, 'ابو خالد');
    await settleFrames(tester, frames: 30);

    // Three answers for the shop name, four for the goods - the fourth being
    // the one that would quietly widen a name into any of its words.
    expect(_chip('مشابه'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('search.productField')),
      'جاكيت',
    );
    await settleFrames(tester, frames: 30);

    await tester.tap(_chip('مشابه'));
    await settleFrames(tester, frames: 30);

    expect(_lastCall(api)['productMatch'], 'similar');
  });

  testWidgets('the goods box alone is a search', (tester) async {
    final _RecordingSearchApi api = _RecordingSearchApi();
    final SearchBloc bloc = await _pumpSearch(tester, api);

    await tester.enterText(find.byType(TextField).first, 'ابو خالد');
    await settleFrames(tester, frames: 30);

    await tester.enterText(
      find.byKey(const ValueKey<String>('search.productField')),
      'جاكيت',
    );
    await settleFrames(tester, frames: 30);

    // Clearing the shop name leaves a question, not an empty screen.
    await tester.enterText(find.byType(TextField).first, '');
    await settleFrames(tester, frames: 30);

    expect(bloc.state.status, isNot(SearchStatus.idle));
    expect(_lastCall(api), <String, Object?>{
      'query': '',
      'match': 'contains',
      'product': 'جاكيت',
      'productMatch': 'contains',
    });
  });

  testWidgets('emptying both boxes puts the screen back to rest', (
    tester,
  ) async {
    final _RecordingSearchApi api = _RecordingSearchApi();
    final SearchBloc bloc = await _pumpSearch(tester, api);

    await tester.enterText(find.byType(TextField).first, 'ابو خالد');
    await settleFrames(tester, frames: 30);
    await tester.enterText(find.byType(TextField).first, '');
    await settleFrames(tester, frames: 30);

    expect(bloc.state.status, SearchStatus.idle);
    expect(bloc.state.businesses, isEmpty);
  });

  // A search for goods alone has no shop name to remember, and the list is of
  // shop names.
  testWidgets('only what was typed in the shop box is remembered', (
    tester,
  ) async {
    final _RecordingSearchApi api = _RecordingSearchApi();
    final SearchBloc bloc = await _pumpSearch(tester, api);

    await tester.enterText(
      find.byKey(const ValueKey<String>('search.productField')),
      'جاكيت',
    );
    await settleFrames(tester, frames: 30);

    expect(bloc.state.history, isEmpty);

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(SearchBloc.historyKey), isNull);
  });

  test('the refinement knows when it is refining nothing', () {
    expect(const SearchRefinement().isPlain, isTrue);
    expect(const SearchRefinement(match: SearchMatch.starts).isPlain, isFalse);
    expect(const SearchRefinement(product: 'جاكيت').isPlain, isFalse);
    expect(const SearchRefinement(product: '   ').isPlain, isTrue);
  });

  // ---------------------------------------------------------------------------
  // Which tab the answer opens on
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // A search that could not be run
  // ---------------------------------------------------------------------------

  // The screen had no failure state, so a network fault, a server error and an
  // empty shelf were one screen saying "no results". A reader reporting "the
  // search returns nothing" could have meant any of the three, and twice in one
  // week it was not clear which.
  testWidgets('a search that could not be run says so, and offers to retry', (
    tester,
  ) async {
    final _FailingApi api = _FailingApi();
    final SearchBloc bloc = SearchBloc(apiService: api);
    addTearDown(bloc.close);

    await pumpLocalized(
      tester,
      BlocProvider<SearchBloc>.value(value: bloc, child: const SearchPage()),
    );

    final Future<SearchState> settled = bloc.stream.firstWhere(
      (SearchState state) => state.status == SearchStatus.failure,
    );
    bloc.add(const SearchSubmitted('بتول'));
    await settled;
    await settleFrames(tester);

    expect(find.byKey(const ValueKey<String>('search.failed')), findsOneWidget);
    expect(find.text('لا توجد نتائج'), findsNothing);

    expect(api.calls, 1);
    await tester.tap(find.text('إعادة المحاولة'));
    await settleFrames(tester);
    expect(api.calls, 2, reason: 'retry asks the same question again');
  });

  testWidgets('a search that found nothing is not a search that failed', (
    tester,
  ) async {
    final SearchBloc bloc = SearchBloc(
      apiService: _TabApi(shopCount: 0, goodsCount: 0, shopsMatched: false),
    );
    addTearDown(bloc.close);

    await pumpLocalized(
      tester,
      BlocProvider<SearchBloc>.value(value: bloc, child: const SearchPage()),
    );

    final Future<SearchState> settled = bloc.stream.firstWhere(
      (SearchState state) => state.status == SearchStatus.success,
    );
    bloc.add(const SearchSubmitted('لا شيء'));
    await settled;
    await settleFrames(tester);

    expect(find.byKey(const ValueKey<String>('search.failed')), findsNothing);
  });

  // ---------------------------------------------------------------------------
  // Which side of the box each mark sits on
  // ---------------------------------------------------------------------------

  /// The marks in the search box, by where they are drawn.
  Future<({Rect glass, Rect clear, Rect box})> boxMarks(
    WidgetTester tester, {
    required TextDirection direction,
  }) async {
    final SearchBloc bloc = SearchBloc(apiService: _FailingApi());
    addTearDown(bloc.close);

    await pumpLocalized(
      tester,
      BlocProvider<SearchBloc>.value(value: bloc, child: const SearchPage()),
      textDirection: direction,
    );

    // The cross appears only once there is something to clear.
    await tester.enterText(find.byType(TextField).first, 'بتول');
    await settleFrames(tester);

    // Scoped to the box being asked about: there are two magnifiers on this
    // screen now, one per box.
    final Finder box = find.byType(TextField).first;

    return (
      glass: tester.getRect(
        find.descendant(
          of: box,
          matching: find.byIcon(MerzoxIcons.searchPageSearch),
        ),
      ),
      clear: tester.getRect(find.byKey(const ValueKey<String>('search.clear'))),
      box: tester.getRect(box),
    );
  }

  testWidgets('in Arabic the glass leads and the cross follows', (
    tester,
  ) async {
    final marks = await boxMarks(tester, direction: TextDirection.rtl);

    expect(
      marks.glass.center.dx,
      greaterThan(marks.box.center.dx),
      reason: 'the magnifier belongs at the right of an Arabic box',
    );
    expect(
      marks.clear.center.dx,
      lessThan(marks.box.center.dx),
      reason: 'and the cross opposite it',
    );
  });

  testWidgets('in English they change sides with the page', (tester) async {
    final marks = await boxMarks(tester, direction: TextDirection.ltr);

    expect(marks.glass.center.dx, lessThan(marks.box.center.dx));
    expect(marks.clear.center.dx, greaterThan(marks.box.center.dx));
  });

  // It drew Material's `chevron_right_rounded` behind an `isRtl` test, and
  // Material mirrors that icon in a right-to-left page itself - so the two
  // turns cancelled and the mark pointed away from the way back.
  testWidgets('the way back is the artboard chevron, pointing back', (
    tester,
  ) async {
    final SearchBloc bloc = SearchBloc(apiService: _FailingApi());
    addTearDown(bloc.close);

    await pumpLocalized(
      tester,
      BlocProvider<SearchBloc>.value(value: bloc, child: const SearchPage()),
    );

    expect(find.byType(MerzoxBackChevron), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);

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

    expect(
      painter.rightward,
      isTrue,
      reason: 'in Arabic the way back is towards the right edge',
    );
  });

  // ---------------------------------------------------------------------------
  // The list of past searches
  // ---------------------------------------------------------------------------

  // It used to open on three invented rows - a pair of shoes and a shop nobody
  // here has heard of - and they could be neither removed one by one nor
  // cleared, because there was nothing behind them to remove.
  testWidgets('there is no list of past searches until there is one', (
    tester,
  ) async {
    final _TabApi api = _TabApi(shopCount: 1, goodsCount: 0);
    final SearchBloc bloc = SearchBloc(apiService: api);
    addTearDown(bloc.close);
    bloc.add(const SearchStarted());

    await pumpLocalized(
      tester,
      BlocProvider<SearchBloc>.value(value: bloc, child: const SearchPage()),
    );

    expect(find.text('تم البحث عنه سابقاً'), findsNothing);
    expect(find.text('مسح الجميع'), findsNothing);

    // Driven through the box, the way a reader does it: emptying a field that
    // was never typed into fires nothing, and the screen would still think a
    // search was in progress.
    await tester.enterText(find.byType(TextField).first, 'بتول');
    await settleFrames(tester, frames: 30);

    // Back to the empty screen, which now has something to show.
    await tester.enterText(find.byType(TextField).first, '');
    await settleFrames(tester, frames: 30);

    expect(find.text('تم البحث عنه سابقاً'), findsOneWidget);
    expect(find.text('بتول'), findsOneWidget);
  });

  testWidgets('a past search can be removed, and all of them cleared', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      SearchBloc.historyKey: <String>['بتول', 'احمر'],
    });

    final SearchBloc bloc = SearchBloc(
      apiService: _TabApi(shopCount: 1, goodsCount: 0),
    );
    addTearDown(bloc.close);
    bloc.add(const SearchStarted());
    await bloc.stream.firstWhere(
      (SearchState state) => state.history.isNotEmpty,
    );

    await pumpLocalized(
      tester,
      BlocProvider<SearchBloc>.value(value: bloc, child: const SearchPage()),
    );

    expect(find.text('بتول'), findsOneWidget);
    expect(find.text('احمر'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('search.history.remove.بتول')),
    );
    await settleFrames(tester);

    expect(find.text('بتول'), findsNothing);
    expect(find.text('احمر'), findsOneWidget);

    await tester.tap(find.text('مسح الجميع'));
    await settleFrames(tester);

    expect(find.text('احمر'), findsNothing);
    expect(find.text('تم البحث عنه سابقاً'), findsNothing);
  });

  // The goods box empties the same way the shop box does.
  testWidgets('the cross on the goods box clears it', (tester) async {
    final _RecordingSearchApi api = _RecordingSearchApi();
    await _pumpSearch(tester, api);

    const Key cross = ValueKey<String>('search.clearProduct');
    expect(find.byKey(cross), findsNothing);

    // Something in the shop box too, so that clearing the goods leaves a
    // question standing and the server is asked it again. Clearing both would
    // rightly ask nothing at all.
    await tester.enterText(find.byType(TextField).first, 'ابو خالد');
    await tester.enterText(
      find.byKey(const ValueKey<String>('search.productField')),
      'جاكيت',
    );
    await settleFrames(tester, frames: 30);

    expect(find.byKey(cross), findsOneWidget);
    expect(_lastCall(api)['product'], 'جاكيت');

    await tester.tap(find.byKey(cross));
    await settleFrames(tester, frames: 30);

    expect(find.byKey(cross), findsNothing);
    expect(_lastCall(api)['product'], '');
  });

  test('the tab is chosen by what was found', () {
    expect(
      SearchState.tabFor(shopsMatchedThemselves: true, hasProducts: true),
      SearchState.storesTab,
    );
    expect(
      SearchState.tabFor(shopsMatchedThemselves: true, hasProducts: false),
      SearchState.storesTab,
    );
    expect(
      SearchState.tabFor(shopsMatchedThemselves: false, hasProducts: true),
      SearchState.productsTab,
      reason: 'goods and no shop: the goods are the answer',
    );
    expect(
      SearchState.tabFor(shopsMatchedThemselves: false, hasProducts: false),
      SearchState.storesTab,
      reason: 'nothing found: there is nothing to choose between',
    );
  });

  /// The tab a fresh answer settles on.
  Future<int> tabAfter(String query, _TabApi api) async {
    final SearchBloc bloc = SearchBloc(apiService: api);
    addTearDown(bloc.close);

    final Future<SearchState> answered = bloc.stream.firstWhere(
      (SearchState state) => state.status == SearchStatus.success,
    );
    bloc.add(SearchSubmitted(query));

    return (await answered).selectedTab;
  }

  test('an answer with shops in it opens on the shops', () async {
    expect(
      await tabAfter('ابو خالد', _TabApi(shopCount: 2, goodsCount: 3)),
      SearchState.storesTab,
    );
  });

  // The case that was reported: `احمر` finds lipstick, and the shops that sell
  // it are listed too - so counting the list opened on a tab of shops.
  test(
    'goods the words found, in shops the words did not, opens on goods',
    () async {
      expect(
        await tabAfter(
          'احمر',
          _TabApi(shopCount: 2, goodsCount: 3, shopsMatched: false),
        ),
        SearchState.productsTab,
      );
    },
  );

  test('an answer with only goods opens on the goods', () async {
    expect(
      await tabAfter(
        'جاكيت',
        _TabApi(shopCount: 0, goodsCount: 3, shopsMatched: false),
      ),
      SearchState.productsTab,
    );
  });

  test('an answer with nothing in it opens on the shops', () async {
    expect(
      await tabAfter(
        'لا شيء',
        _TabApi(shopCount: 0, goodsCount: 0, shopsMatched: false),
      ),
      SearchState.storesTab,
    );
  });

  // A reader who disagrees with the guess keeps their choice until the next
  // answer arrives - which is a new question, and a new guess.
  test('a reader may overrule the guess, until the next answer', () async {
    final SearchBloc bloc = SearchBloc(
      apiService: _TabApi(shopCount: 2, goodsCount: 3),
    );
    addTearDown(bloc.close);

    Future<SearchState> answered() => bloc.stream.firstWhere(
      (SearchState state) => state.status == SearchStatus.success,
    );

    Future<SearchState> first = answered();
    bloc.add(const SearchSubmitted('ابو خالد'));
    expect((await first).selectedTab, SearchState.storesTab);

    bloc.add(const SearchTabChanged(SearchState.productsTab));
    await bloc.stream.firstWhere(
      (SearchState state) => state.selectedTab == SearchState.productsTab,
    );

    final Future<SearchState> second = answered();
    bloc.add(const SearchSubmitted('ابو سعيد'));
    expect((await second).selectedTab, SearchState.storesTab);
  });
}

/// Answers with a stated number of shops and goods in it.
class _TabApi extends ApiService {
  final int shopCount;
  final int goodsCount;
  final bool shopsMatched;

  _TabApi({
    required this.shopCount,
    required this.goodsCount,
    this.shopsMatched = true,
  });

  @override
  Future<SearchApiResponse> searchCatalog({
    required String query,
    String match = 'contains',
    String product = '',
    String productMatch = 'contains',
    int limit = 30,
  }) async {
    return SearchApiResponse(
      query: query,
      shopsMatchedThemselves: shopsMatched,
      products: <SearchProductApiModel>[
        for (int i = 0; i < goodsCount; i += 1)
          SearchProductApiModel.fromJson(_goods(i)),
      ],
      businesses: <SearchBusinessApiModel>[
        for (int i = 0; i < shopCount; i += 1)
          SearchBusinessApiModel.fromJson(<String, dynamic>{
            'id': 'b$i',
            'publicId': 'MXB-$i',
            'name': 'متجر $i',
          }),
      ],
    );
  }
}

/// A product as the server sends one. Built in full rather than sketched,
/// because a half-built one throws on the way in and the bloc reports a
/// failure - which looks exactly like the search having found nothing.
Map<String, dynamic> _goods(int index) => <String, dynamic>{
  'id': 'product-$index',
  'name': 'منتج $index',
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
    'id': 'b',
    'publicId': 'MXB-1',
    'name': 'متجر',
    'category': '',
    'logoUrl': '',
    'products': <String>[],
    'productCount': 0,
    'rating': 4,
    'ratingCount': 1,
    'followerCount': 0,
    'viewCount': 0,
    'colorValue': 0xffdeeef8,
    'address': '',
  },
};

/// A server that cannot be reached.
class _FailingApi extends ApiService {
  int calls = 0;

  @override
  Future<SearchApiResponse> searchCatalog({
    required String query,
    String match = 'contains',
    String product = '',
    String productMatch = 'contains',
    int limit = 30,
  }) async {
    calls += 1;
    throw StateError('no server in this test');
  }
}
