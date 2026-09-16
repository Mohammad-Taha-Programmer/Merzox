import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/search/bloc/search_bloc.dart';
import 'package:merzox/features/search/bloc/search_event.dart';
import 'package:merzox/features/search/bloc/search_state.dart';
import 'package:merzox/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers that arrive in the wrong order.
///
/// Somebody types `بتول` a letter at a time. Each pause longer than the
/// debounce sends a search, so `ب` is asked before `بتول` is - and `ب` is the
/// broad one, matching a great many shops, so it is the slow one. It comes
/// back last and overwrites the narrow answer that was already on screen.
///
/// What the reader sees is the shop they wanted *and* a long list of shops
/// that have nothing to do with what they typed, which is exactly what was
/// reported.
class _SlowFirstApi extends ApiService {
  final Map<String, Completer<void>> gates = <String, Completer<void>>{};
  final List<String> asked = <String>[];

  @override
  Future<SearchApiResponse> searchCatalog({
    required String query,
    String match = 'contains',
    String product = '',
    String productMatch = 'contains',
    int limit = 30,
  }) async {
    asked.add(query);
    await (gates[query] ??= Completer<void>()).future;

    return SearchApiResponse(
      query: query,
      products: const <SearchProductApiModel>[],
      businesses: <SearchBusinessApiModel>[
        for (int i = 0; i < (query.length == 1 ? 40 : 1); i += 1)
          SearchBusinessApiModel.fromJson(<String, dynamic>{
            'id': '$query-$i',
            'publicId': 'MXB-$query-$i',
            'name': query.length == 1 ? 'متجر مرزوكس التجريبي $i' : 'البتول',
          }),
      ],
    );
  }

  void answer(String query) {
    (gates[query] ??= Completer<void>()).complete();
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('a slow broad answer does not overwrite the narrow one', () async {
    final _SlowFirstApi api = _SlowFirstApi();
    final SearchBloc bloc = SearchBloc(apiService: api);
    addTearDown(bloc.close);

    // Both in flight: the letter first, the word second.
    bloc.add(const SearchSubmitted('ب'));
    await _settle();
    bloc.add(const SearchSubmitted('بتول'));
    await _settle();

    expect(api.asked, <String>['ب', 'بتول']);

    // The narrow one comes back first and is shown.
    api.answer('بتول');
    await _settle();
    await _settle();

    expect(bloc.state.businesses.single.name, 'البتول');

    // Then the broad one lands. It is an answer to a question nobody is
    // asking any more.
    api.answer('ب');
    await _settle();
    await _settle();

    expect(
      bloc.state.businesses.map((b) => b.name),
      <String>['البتول'],
      reason:
          'the answer to `ب` arrived after the answer to `بتول` and replaced '
          'it with forty shops that have nothing to do with what was typed',
    );
    expect(bloc.state.query, 'بتول');
    expect(bloc.state.status, SearchStatus.success);
  });

  // A latent fault the staleness check turned up, and the reason it was
  // invisible: the result of the search overwrote the damage a moment later.
  //
  // `emit(state.copyWith(..., history: await _loadHistory()))` reads `state`
  // before it evaluates the argument, so the state it emits is built on a
  // snapshot taken before the await - and anything written during the await is
  // wiped by the arrival of the history list.
  test('the list of past searches does not wipe what is being typed', () async {
    final _SlowFirstApi api = _SlowFirstApi();
    final SearchBloc bloc = SearchBloc(apiService: api);
    addTearDown(bloc.close);

    bloc.add(const SearchStarted());
    bloc.add(const SearchSubmitted('بتول'));
    await _settle();
    await _settle();

    api.answer('بتول');
    await _settle();
    await _settle();
    await _settle();

    expect(bloc.state.query, 'بتول');
    expect(bloc.state.status, SearchStatus.success);
    expect(bloc.state.businesses.single.name, 'البتول');
  });
}
