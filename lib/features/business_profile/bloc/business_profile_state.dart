import 'package:merzox/services/api_service.dart';

enum BusinessProfileStatus { initial, loading, ready, savingReview, failure }

final class BusinessProfileState {
  final BusinessProfileStatus status;
  final String businessId;
  final int mainTabIndex;
  final String productClassification;
  final List<BusinessProductApiModel> products;
  final List<BusinessReviewApiModel> reviews;
  final Set<String> likedProductIds;
  final String? errorMessage;

  const BusinessProfileState({
    this.status = BusinessProfileStatus.initial,
    this.businessId = '',
    this.mainTabIndex = 0,
    this.productClassification = 'new',
    this.products = const [],
    this.reviews = const [],
    this.likedProductIds = const {},
    this.errorMessage,
  });

  BusinessProfileState copyWith({
    BusinessProfileStatus? status,
    String? businessId,
    int? mainTabIndex,
    String? productClassification,
    List<BusinessProductApiModel>? products,
    List<BusinessReviewApiModel>? reviews,
    Set<String>? likedProductIds,
    String? errorMessage,
  }) {
    return BusinessProfileState(
      status: status ?? this.status,
      businessId: businessId ?? this.businessId,
      mainTabIndex: mainTabIndex ?? this.mainTabIndex,
      productClassification:
          productClassification ?? this.productClassification,
      products: products ?? this.products,
      reviews: reviews ?? this.reviews,
      likedProductIds: likedProductIds ?? this.likedProductIds,
      errorMessage: errorMessage,
    );
  }
}
