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
  const CartCheckoutRequested();
}
