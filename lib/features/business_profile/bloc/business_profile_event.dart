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

final class BusinessProfileDetailsRetryRequested extends BusinessProfileEvent {
  const BusinessProfileDetailsRetryRequested();
}

final class BusinessProfileProductsRetryRequested extends BusinessProfileEvent {
  const BusinessProfileProductsRetryRequested();
}

final class BusinessProfileReviewsRetryRequested extends BusinessProfileEvent {
  const BusinessProfileReviewsRetryRequested();
}

final class BusinessProfileReviewEligibilityRetryRequested
    extends BusinessProfileEvent {
  const BusinessProfileReviewEligibilityRetryRequested();
}

/// Pull to refresh: fetch the whole shop again, not the tab in front of you.
///
/// The three tabs are three requests and a reader who pulls has no way to say
/// which one they meant. They mean the shop.
final class BusinessProfileRefreshRequested extends BusinessProfileEvent {
  const BusinessProfileRefreshRequested();
}
