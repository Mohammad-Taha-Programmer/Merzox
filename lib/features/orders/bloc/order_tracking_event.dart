sealed class OrderTrackingEvent {
  const OrderTrackingEvent();
}

final class OrderTrackingStarted extends OrderTrackingEvent {
  const OrderTrackingStarted();
}

final class OrderTrackingRefreshRequested extends OrderTrackingEvent {
  const OrderTrackingRefreshRequested();
}

final class OrderTrackingCancelRequested extends OrderTrackingEvent {
  final String reason;

  const OrderTrackingCancelRequested({this.reason = ''});
}

final class OrderTrackingAddressChanged extends OrderTrackingEvent {
  final String deliveryAddress;

  const OrderTrackingAddressChanged(this.deliveryAddress);
}

/// The design asks for the store rating right on the tracking screen once the
/// order lands, so it is part of this flow rather than a separate page.
final class OrderTrackingReviewSubmitted extends OrderTrackingEvent {
  final int rating;
  final String comment;

  const OrderTrackingReviewSubmitted({
    required this.rating,
    required this.comment,
  });
}
