import 'dart:ui';

import 'package:merzox/services/api_service.dart';

sealed class ProductDetailsEvent {
  const ProductDetailsEvent();
}

final class ProductDetailsStarted extends ProductDetailsEvent {
  final String businessId;
  final BusinessProductApiModel initialProduct;

  const ProductDetailsStarted({
    required this.businessId,
    required this.initialProduct,
  });
}

final class ProductDetailsImageChanged extends ProductDetailsEvent {
  final int index;

  const ProductDetailsImageChanged(this.index);
}

final class ProductDetailsTabChanged extends ProductDetailsEvent {
  final int index;

  const ProductDetailsTabChanged(this.index);
}

final class ProductDetailsQuantityIncremented extends ProductDetailsEvent {
  const ProductDetailsQuantityIncremented();
}

final class ProductDetailsQuantityDecremented extends ProductDetailsEvent {
  const ProductDetailsQuantityDecremented();
}

final class ProductDetailsReviewSubmitted extends ProductDetailsEvent {
  final int rating;
  final String comment;

  const ProductDetailsReviewSubmitted({
    required this.rating,
    required this.comment,
  });
}

final class ProductDetailsAddToCartPressed extends ProductDetailsEvent {
  const ProductDetailsAddToCartPressed();
}

final class ProductDetailsBuyNowPressed extends ProductDetailsEvent {
  const ProductDetailsBuyNowPressed();
}

final class ProductDetailsReloadRequested extends ProductDetailsEvent {
  const ProductDetailsReloadRequested();
}

final class ProductDetailsReviewsRetryRequested extends ProductDetailsEvent {
  const ProductDetailsReviewsRetryRequested();
}

final class ProductDetailsShareRequested extends ProductDetailsEvent {
  final String businessName;
  final String languageCode;
  final Rect? sharePositionOrigin;

  const ProductDetailsShareRequested({
    required this.businessName,
    required this.languageCode,
    this.sharePositionOrigin,
  });
}
