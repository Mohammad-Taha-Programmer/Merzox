import 'package:merzox/services/api_service.dart';

enum BusinessProfileStatus { initial, loading, ready, savingReview, failure }

enum BusinessProfileSectionStatus { initial, loading, ready, failure }

final class BusinessProfileState {
  final BusinessProfileStatus status;
  final String businessId;
  final int mainTabIndex;
  final String productClassification;
  final BusinessDetailApiModel? business;
  final List<BusinessProductApiModel> products;
  final List<BusinessReviewApiModel> reviews;
  final Set<String> likedProductIds;
  final BusinessProfileSectionStatus detailsStatus;
  final BusinessProfileSectionStatus productsStatus;
  final BusinessProfileSectionStatus reviewsStatus;
  final String detailsError;
  final String productsError;
  final String reviewsError;
  final String errorMessage;

  const BusinessProfileState({
    this.status = BusinessProfileStatus.initial,
    this.businessId = '',
    this.mainTabIndex = 0,
    this.productClassification = 'new',
    this.business,
    this.products = const [],
    this.reviews = const [],
    this.likedProductIds = const {},
    this.detailsStatus = BusinessProfileSectionStatus.initial,
    this.productsStatus = BusinessProfileSectionStatus.initial,
    this.reviewsStatus = BusinessProfileSectionStatus.initial,
    this.detailsError = '',
    this.productsError = '',
    this.reviewsError = '',
    this.errorMessage = '',
  });

  BusinessProfileState copyWith({
    BusinessProfileStatus? status,
    String? businessId,
    int? mainTabIndex,
    String? productClassification,
    BusinessDetailApiModel? business,
    List<BusinessProductApiModel>? products,
    List<BusinessReviewApiModel>? reviews,
    Set<String>? likedProductIds,
    BusinessProfileSectionStatus? detailsStatus,
    BusinessProfileSectionStatus? productsStatus,
    BusinessProfileSectionStatus? reviewsStatus,
    String? detailsError,
    String? productsError,
    String? reviewsError,
    String? errorMessage,
  }) {
    return BusinessProfileState(
      status: status ?? this.status,
      businessId: businessId ?? this.businessId,
      mainTabIndex: mainTabIndex ?? this.mainTabIndex,
      productClassification:
          productClassification ?? this.productClassification,
      business: business ?? this.business,
      products: products ?? this.products,
      reviews: reviews ?? this.reviews,
      likedProductIds: likedProductIds ?? this.likedProductIds,
      detailsStatus: detailsStatus ?? this.detailsStatus,
      productsStatus: productsStatus ?? this.productsStatus,
      reviewsStatus: reviewsStatus ?? this.reviewsStatus,
      detailsError: detailsError ?? this.detailsError,
      productsError: productsError ?? this.productsError,
      reviewsError: reviewsError ?? this.reviewsError,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
