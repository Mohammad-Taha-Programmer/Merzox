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

  /// The address the buyer chose from their book. Empty falls back to the
  /// profile's single stored address, which is what an account that predates
  /// the address book still has.
  final String deliveryAddress;

  const CartCheckoutRequested({
    this.deliveryOption = 'standard',
    this.deliveryAddress = '',
  });
}
