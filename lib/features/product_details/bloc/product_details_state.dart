import 'package:merzox/services/api_service.dart';

enum ProductDetailsStatus {
  initial,
  loading,
  ready,
  savingReview,
  action,
  failure,
}

final class ProductDetailsState {
  final ProductDetailsStatus status;
  final String businessId;
  final BusinessProductApiModel? product;
  final List<BusinessReviewApiModel> reviews;
  final int selectedImageIndex;
  final int selectedTabIndex;
  final int quantity;
  final String selectedDegree;
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
    this.selectedDegree = '01',
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
    String? selectedDegree,
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
      selectedDegree: selectedDegree ?? this.selectedDegree,
      message: message,
      errorMessage: errorMessage,
    );
  }
}
