import 'package:merzox/services/api_service.dart';
import 'package:merzox/services/review_eligibility_service.dart';

enum ProductDetailsStatus {
  initial,
  loading,
  ready,
  savingReview,
  sharing,
  action,
  failure,
}

enum ProductDetailsSectionStatus { initial, loading, ready, failure }

final class ProductDetailsState {
  static const Object _keepSelectedVariantId = Object();

  final ProductDetailsStatus status;
  final String businessId;
  final BusinessProductApiModel? product;
  final List<BusinessReviewApiModel> reviews;
  final int selectedImageIndex;
  final int selectedTabIndex;
  final int quantity;

  /// Null means no variant has been selected.
  ///
  /// For simple products this must remain null. For variant products an exact
  /// active PUBLIC variant must be selected before a purchase action.
  final String? selectedVariantId;

  final ProductDetailsSectionStatus detailsStatus;
  final ProductDetailsSectionStatus reviewsStatus;
  final String detailsError;
  final String reviewsError;
  final String? message;
  final String? errorMessage;
  final ReviewEligibilityStatus reviewEligibilityStatus;

  const ProductDetailsState({
    this.status = ProductDetailsStatus.initial,
    this.businessId = '',
    this.product,
    this.reviews = const [],
    this.selectedImageIndex = 0,
    this.selectedTabIndex = 0,
    this.quantity = 1,
    this.selectedVariantId,
    this.detailsStatus = ProductDetailsSectionStatus.initial,
    this.reviewsStatus = ProductDetailsSectionStatus.initial,
    this.detailsError = '',
    this.reviewsError = '',
    this.message,
    this.errorMessage,
    this.reviewEligibilityStatus = ReviewEligibilityStatus.unchecked,
  });

  BusinessProductVariantApiModel? get selectedVariant {
    final currentProduct = product;
    final id = selectedVariantId;

    if (currentProduct == null || !currentProduct.hasVariants || id == null) {
      return null;
    }

    for (final variant in currentProduct.variants) {
      if (variant.id == id) return variant;
    }

    return null;
  }

  /// Selection is requested only when there is at least one purchasable
  /// variant. An all-sold-out product reports stock truth instead.
  bool get variantSelectionRequired {
    final currentProduct = product;

    return currentProduct != null &&
        currentProduct.hasVariants &&
        currentProduct.inStock &&
        selectedVariant == null;
  }

  /// Availability of the exact sellable identity represented by this state.
  bool get selectedSellableInStock {
    final currentProduct = product;

    if (currentProduct == null) return false;
    if (!currentProduct.hasVariants) return currentProduct.inStock;

    return selectedVariant?.inStock ?? false;
  }

  ProductDetailsState copyWith({
    ProductDetailsStatus? status,
    String? businessId,
    BusinessProductApiModel? product,
    List<BusinessReviewApiModel>? reviews,
    int? selectedImageIndex,
    int? selectedTabIndex,
    int? quantity,
    Object? selectedVariantId = _keepSelectedVariantId,
    ProductDetailsSectionStatus? detailsStatus,
    ProductDetailsSectionStatus? reviewsStatus,
    String? detailsError,
    String? reviewsError,
    String? message,
    String? errorMessage,
    ReviewEligibilityStatus? reviewEligibilityStatus,
  }) {
    return ProductDetailsState(
      status: status ?? this.status,
      businessId: businessId ?? this.businessId,
      product: product ?? this.product,
      reviews: reviews ?? this.reviews,
      selectedImageIndex: selectedImageIndex ?? this.selectedImageIndex,
      selectedTabIndex: selectedTabIndex ?? this.selectedTabIndex,
      quantity: quantity ?? this.quantity,
      selectedVariantId: identical(selectedVariantId, _keepSelectedVariantId)
          ? this.selectedVariantId
          : selectedVariantId as String?,
      detailsStatus: detailsStatus ?? this.detailsStatus,
      reviewsStatus: reviewsStatus ?? this.reviewsStatus,
      detailsError: detailsError ?? this.detailsError,
      reviewsError: reviewsError ?? this.reviewsError,
      message: message,
      errorMessage: errorMessage,
      reviewEligibilityStatus:
          reviewEligibilityStatus ?? this.reviewEligibilityStatus,
    );
  }
}
