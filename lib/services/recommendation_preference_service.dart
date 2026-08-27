import 'package:merzox/services/api_service.dart';

final class RecommendationPreferenceSnapshot {
  final bool enabled;
  final String status;

  const RecommendationPreferenceSnapshot({
    required this.enabled,
    required this.status,
  });

  factory RecommendationPreferenceSnapshot.fromUser(AuthApiUser user) {
    final consent = user.permissionConsents.aiPersonalization;

    return RecommendationPreferenceSnapshot(
      enabled: user.permissions.aiPersonalization && consent.isGranted,
      status: consent.status,
    );
  }
}

abstract interface class RecommendationPreferenceGateway {
  Future<RecommendationPreferenceSnapshot> load({required String token});

  Future<RecommendationPreferenceSnapshot> update({
    required String token,
    required bool enabled,
  });
}

final class RecommendationPreferenceService
    implements RecommendationPreferenceGateway {
  final ApiService _apiService;

  RecommendationPreferenceService({ApiService? apiService})
    : _apiService = apiService ?? ApiService();

  @override
  Future<RecommendationPreferenceSnapshot> load({required String token}) async {
    final user = await _apiService.me(token: token);

    return RecommendationPreferenceSnapshot.fromUser(user);
  }

  @override
  Future<RecommendationPreferenceSnapshot> update({
    required String token,
    required bool enabled,
  }) async {
    final user = await _apiService.updatePermissions(
      token: token,
      aiPersonalization: enabled,
    );

    // Never trust the requested value. The complete user projection returned
    // by the server is authoritative, including the consent lifecycle.
    return RecommendationPreferenceSnapshot.fromUser(user);
  }
}
