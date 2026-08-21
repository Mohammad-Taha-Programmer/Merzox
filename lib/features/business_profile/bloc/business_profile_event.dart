sealed class BusinessProfileEvent {
  const BusinessProfileEvent();
}

final class BusinessProfileStarted extends BusinessProfileEvent {
  final String businessId;

  const BusinessProfileStarted(this.businessId);
}

final class BusinessProfileMainTabChanged extends BusinessProfileEvent {
  final int index;

  const BusinessProfileMainTabChanged(this.index);
}

final class BusinessProfileProductFilterChanged extends BusinessProfileEvent {
  final String classification;

  const BusinessProfileProductFilterChanged(this.classification);
}

final class BusinessProfileProductLikeToggled extends BusinessProfileEvent {
  final String productId;

  const BusinessProfileProductLikeToggled(this.productId);
}

final class BusinessProfileReviewSubmitted extends BusinessProfileEvent {
  final int rating;
  final String comment;

  const BusinessProfileReviewSubmitted({
    required this.rating,
    required this.comment,
  });
}
