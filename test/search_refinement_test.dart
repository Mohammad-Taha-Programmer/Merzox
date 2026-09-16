import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
