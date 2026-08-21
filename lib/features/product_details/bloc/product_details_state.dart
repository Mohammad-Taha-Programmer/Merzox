import 'package:merzox/services/api_service.dart';

enum ProductDetailsStatus {
  initial,
  loading,
  ready,
  savingReview,
  action,
  failure,
}

enum ProductDetailsSectionStatus { initial, loading, ready, failure }

final class ProductDetailsState {
  final ProductDetailsStatus status;
  final String businessId;
  final BusinessProductApiModel? product;
  final List<BusinessReviewApiModel> reviews;
  final int selectedImageIndex;
  final int selectedTabIndex;
  final int quantity;
  final ProductDetailsSectionStatus detailsStatus;
  final ProductDetailsSectionStatus reviewsStatus;
  final String detailsError;
  final String reviewsError;
  final String? message;
  final String? errorMessage;

  const ProductDetailsState({
    this.status = ProductDetailsStatus.initial,
    this.businessId = '',
    this.product,
    this.reviews = const [],
    this.selectedImageIndex = 0,
    this.selectedTabIndex = 0,
    this.quantity = 1,
    this.detailsStatus = ProductDetailsSectionStatus.initial,
    this.reviewsStatus = ProductDetailsSectionStatus.initial,
    this.detailsError = '',
    this.reviewsError = '',
    this.message,
    this.errorMessage,
  });

  ProductDetailsState copyWith({
    ProductDetailsStatus? status,
    String? businessId,
    BusinessProductApiModel? product,
    List<BusinessReviewApiModel>? reviews,
    int? selectedImageIndex,
    int? selectedTabIndex,
    int? quantity,
    ProductDetailsSectionStatus? detailsStatus,
    ProductDetailsSectionStatus? reviewsStatus,
    String? detailsError,
    String? reviewsError,
    String? message,
    String? errorMessage,
  }) {
    return ProductDetailsState(
      status: status ?? this.status,
      businessId: businessId ?? this.businessId,
      product: product ?? this.product,
      reviews: reviews ?? this.reviews,
      selectedImageIndex: selectedImageIndex ?? this.selectedImageIndex,
      selectedTabIndex: selectedTabIndex ?? this.selectedTabIndex,
      quantity: quantity ?? this.quantity,
      detailsStatus: detailsStatus ?? this.detailsStatus,
      reviewsStatus: reviewsStatus ?? this.reviewsStatus,
      detailsError: detailsError ?? this.detailsError,
      reviewsError: reviewsError ?? this.reviewsError,
      message: message,
      errorMessage: errorMessage,
    );
  }
}
