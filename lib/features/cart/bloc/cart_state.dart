enum CartStatus { initial, loading, ready, checkingOut, failure }

final class CartItem {
  final String raw;
  final String productId;
  final String businessId;
  final String name;
  final double price;
  final String imageUrl;
  final int quantity;

  const CartItem({
    required this.raw,
    required this.productId,
    required this.businessId,
    required this.name,
    required this.price,
    required this.imageUrl,
    required this.quantity,
  });

  double get total => price * quantity;
}

final class CartState {
  final CartStatus status;
  final List<CartItem> items;
  final String messageCode;
  final String errorMessage;

  const CartState({
    this.status = CartStatus.initial,
    this.items = const [],
    this.messageCode = '',
    this.errorMessage = '',
  });

  double get subtotal => items.fold(0, (sum, item) => sum + item.total);

  CartState copyWith({
    CartStatus? status,
    List<CartItem>? items,
    String? messageCode,
    String? errorMessage,
  }) {
    return CartState(
      status: status ?? this.status,
      items: items ?? this.items,
      messageCode: messageCode ?? this.messageCode,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
