import 'package:merzox/services/api_service.dart';
import 'package:merzox/services/recommendation_preference_service.dart';

typedef RecommendationUserLoader =
    Future<AuthApiUser> Function({required String token});

typedef RecommendationCatalogLoader =
    Future<RecommendationApiResponse> Function({required String token});

final class HomeRecommendationSnapshot {
  final bool consentEnabled;
  final bool personalized;
  final List<String> preferenceCategories;
  final List<SearchBusinessApiModel> businesses;

  const HomeRecommendationSnapshot({
    required this.consentEnabled,
    this.personalized = false,
    this.preferenceCategories = const [],
    this.businesses = const [],
  });

  const HomeRecommendationSnapshot.disabled() : this(consentEnabled: false);
}

abstract interface class HomeRecommendationGateway {
  Future<HomeRecommendationSnapshot> load({required String token});
}

final class RecommendationService implements HomeRecommendationGateway {
  final ApiService _apiService;
  final RecommendationUserLoader? _userLoader;
  final RecommendationCatalogLoader? _catalogLoader;

  RecommendationService({
    ApiService? apiService,
    RecommendationUserLoader? userLoader,
    RecommendationCatalogLoader? catalogLoader,
  }) : _apiService = apiService ?? ApiService(),
       _userLoader = userLoader,
       _catalogLoader = catalogLoader;

  @override
  Future<HomeRecommendationSnapshot> load({required String token}) async {
    final user = _userLoader != null
        ? await _userLoader(token: token)
        : await _apiService.me(token: token);

    final consent = RecommendationPreferenceSnapshot.fromUser(user);

    // Client-side fail-closed fence:
    // do not even call the recommendation endpoint unless the complete
    // authoritative user projection confirms both permission + consent.
    if (!consent.enabled) {
      return const HomeRecommendationSnapshot.disabled();
    }

    final response = _catalogLoader != null
        ? await _catalogLoader(token: token)
        : await _apiService.recommendations(token: token);

    // Backend also enforces the same authority. A contradictory successful
    // response is a contract failure rather than a reason to widen access.
    if (!response.consentGranted) {
      throw const ApiContractException(
        'recommendations',
        'server returned recommendations without granted consent',
      );
    }

    return HomeRecommendationSnapshot(
      consentEnabled: true,
      personalized: response.personalized,
      preferenceCategories: response.preferenceCategories,
      businesses: response.recommendations,
    );
  }
}
