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

/// How many of one line the basket should hold.
///
/// Carries the stored line verbatim rather than an index: the list is
/// revalidated and rewritten on every load, so an index taken before that is
/// not a promise about which line it points at.
final class CartItemQuantityChanged extends CartEvent {
  final String raw;
  final int quantity;

  const CartItemQuantityChanged({required this.raw, required this.quantity});
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
