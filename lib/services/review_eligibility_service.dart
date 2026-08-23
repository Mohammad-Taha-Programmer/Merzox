import 'package:dio/dio.dart';
import 'package:merzox/services/api_service.dart';

enum ReviewEligibilityReason {
  customerAccountRequired,
  deliveredPurchaseRequired,
}

enum ReviewEligibilityStatus {
  unchecked,
  checking,
  eligible,
  loginRequired,
  customerAccountRequired,
  deliveredPurchaseRequired,
  failure,
}

final class ReviewEligibilityDecision {
  final bool eligible;
  final ReviewEligibilityReason? reason;

  const ReviewEligibilityDecision({
    required this.eligible,
    required this.reason,
  });
}

abstract interface class ReviewEligibilityGateway {
  Future<ReviewEligibilityDecision> businessEligibility({
    required String token,
    required String businessId,
  });

  Future<ReviewEligibilityDecision> productEligibility({
    required String token,
    required String businessId,
    required String productId,
  });
}

final class ReviewEligibilityService implements ReviewEligibilityGateway {
  final Dio _dio;

  ReviewEligibilityService({Dio? dio, String? baseUrl})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl ?? ApiService.defaultBaseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
              headers: const {'Content-Type': 'application/json'},
            ),
          );

  @override
  Future<ReviewEligibilityDecision> businessEligibility({
    required String token,
    required String businessId,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/businesses/$businessId/review-eligibility',
      options: _authOptions(token),
    );

    return _parse(response.data);
  }

  @override
  Future<ReviewEligibilityDecision> productEligibility({
    required String token,
    required String businessId,
    required String productId,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/businesses/$businessId/products/$productId/review-eligibility',
      options: _authOptions(token),
    );

    return _parse(response.data);
  }

  Options _authOptions(String token) {
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  ReviewEligibilityDecision _parse(Map<String, dynamic>? response) {
    final data = response?['data'];

    if (data is! Map<String, dynamic>) {
      throw const ApiContractException(
        'reviewEligibility',
        'response did not contain data',
      );
    }

    final rawEligibility = data['eligibility'];

    if (rawEligibility is! Map<String, dynamic>) {
      throw const ApiContractException(
        'reviewEligibility',
        'response did not contain eligibility',
      );
    }

    final eligible = rawEligibility['eligible'];

    if (eligible is! bool) {
      throw const ApiContractException(
        'reviewEligibility',
        'eligibility.eligible must be a boolean',
      );
    }

    final rawReason = rawEligibility['reason'];

    if (eligible) {
      if (rawReason != null) {
        throw const ApiContractException(
          'reviewEligibility',
          'eligible response must carry a null reason',
        );
      }

      return const ReviewEligibilityDecision(eligible: true, reason: null);
    }

    final reason = switch (rawReason) {
      'customerAccountRequired' =>
        ReviewEligibilityReason.customerAccountRequired,
      'deliveredPurchaseRequired' =>
        ReviewEligibilityReason.deliveredPurchaseRequired,
      _ => throw const ApiContractException(
        'reviewEligibility',
        'ineligible response carried an unknown reason',
      ),
    };

    return ReviewEligibilityDecision(eligible: false, reason: reason);
  }
}

ReviewEligibilityStatus statusForReviewDecision(
  ReviewEligibilityDecision decision,
) {
  if (decision.eligible) {
    return ReviewEligibilityStatus.eligible;
  }

  return switch (decision.reason) {
    ReviewEligibilityReason.customerAccountRequired =>
      ReviewEligibilityStatus.customerAccountRequired,
    ReviewEligibilityReason.deliveredPurchaseRequired =>
      ReviewEligibilityStatus.deliveredPurchaseRequired,
    null => ReviewEligibilityStatus.failure,
  };
}
