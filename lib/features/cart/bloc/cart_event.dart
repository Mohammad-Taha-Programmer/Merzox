sealed class CartEvent {
  const CartEvent();
}

final class CartStarted extends CartEvent {
  const CartStarted();
}

final class CartItemRemoved extends CartEvent {
  final String raw;

  const CartItemRemoved(this.raw);
}

final class CartCheckoutRequested extends CartEvent {
  /// The delivery tier the buyer picked, by name. Its price is the server's.
  final String deliveryOption;

  const CartCheckoutRequested({this.deliveryOption = 'standard'});
}
