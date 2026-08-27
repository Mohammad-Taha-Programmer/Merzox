import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/features/home/presentation/bloc/home_bloc.dart';
import 'package:merzox/features/home/presentation/bloc/home_event.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/services/recommendation_service.dart';

class FakeGateway implements HomeRecommendationGateway {
  HomeRecommendationSnapshot result =
      const HomeRecommendationSnapshot.disabled();

  Future<HomeRecommendationSnapshot> Function()? handler;

  int calls = 0;

  @override
  Future<HomeRecommendationSnapshot> load({required String token}) async {
    calls += 1;
    return handler != null ? handler!() : result;
  }
}

Future<AuthSessionSnapshot> authenticated() async =>
    const AuthSessionSnapshot(type: AuthSessionType.customer, token: 'token');

Future<AuthSessionSnapshot> guest() async =>
    const AuthSessionSnapshot(type: AuthSessionType.unauthenticated);

SearchBusinessApiModel business() => SearchBusinessApiModel.fromJson({
  'id': 'b1',
  'publicId': 'B1',
  'name': 'Store',
  'category': 'Food',
});

void main() {
  test('guest refresh performs zero recommendation reads', () async {
    final gateway = FakeGateway();

    final bloc = HomeBloc(
      recommendationGateway: gateway,
      recommendationSessionReader: guest,
    );

    addTearDown(bloc.close);

    bloc.add(const HomeRecommendationsRefreshRequested());

    await bloc.stream.first;

    expect(gateway.calls, 0);
    expect(bloc.state.recommendedBusinesses, isEmpty);
  });

  test('granted snapshot reaches Home state', () async {
    final gateway = FakeGateway()
      ..result = HomeRecommendationSnapshot(
        consentEnabled: true,
        personalized: true,
        preferenceCategories: const ['Food'],
        businesses: [business()],
      );

    final bloc = HomeBloc(
      recommendationGateway: gateway,
      recommendationSessionReader: authenticated,
    );

    addTearDown(bloc.close);

    final ready = bloc.stream.firstWhere(
      (state) =>
          state.recommendationConsentEnabled &&
          state.recommendedBusinesses.isNotEmpty,
    );

    bloc.add(const HomeRecommendationsRefreshRequested());

    final state = await ready;

    expect(state.recommendedBusinesses.single.id, 'b1');
    expect(state.recommendationsPersonalized, isTrue);
  });

  test('refresh clears stale results before revalidation', () async {
    final gateway = FakeGateway()
      ..result = HomeRecommendationSnapshot(
        consentEnabled: true,
        personalized: true,
        businesses: [business()],
      );

    final bloc = HomeBloc(
      recommendationGateway: gateway,
      recommendationSessionReader: authenticated,
    );

    addTearDown(bloc.close);

    final first = bloc.stream.firstWhere(
      (state) => state.recommendedBusinesses.isNotEmpty,
    );

    bloc.add(const HomeRecommendationsRefreshRequested());

    await first;

    final pending = Completer<HomeRecommendationSnapshot>();

    gateway.handler = () => pending.future;

    final cleared = bloc.stream.firstWhere(
      (state) =>
          !state.recommendationConsentEnabled &&
          state.recommendedBusinesses.isEmpty,
    );

    bloc.add(const HomeRecommendationsRefreshRequested());

    await cleared;

    pending.complete(const HomeRecommendationSnapshot.disabled());
  });
}
