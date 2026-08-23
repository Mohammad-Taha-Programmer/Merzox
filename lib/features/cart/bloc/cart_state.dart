enum CartStatus { initial, loading, ready, checkingOut, failure }

final class CartItem {
  final String raw;
  final String productId;
  final String businessId;
  final String name;

  /// The server-derived sale price as of the last successful revalidation.
  /// Display only - the backend reprices every line at checkout.
  final double price;

  final String imageUrl;
  final int quantity;

  /// Availability as of the last successful revalidation. `true` when the
  /// product could not be re-read, because a failed refresh is not evidence
  /// that something sold out - the server still decides at checkout.
  final bool inStock;

  const CartItem({
    required this.raw,
    required this.productId,
    required this.businessId,
    required this.name,
    required this.price,
    required this.imageUrl,
    required this.quantity,
    this.inStock = true,
  });

  double get total => price * quantity;

  CartItem copyWith({
    String? raw,
    String? name,
    double? price,
    String? imageUrl,
    bool? inStock,
  }) {
    return CartItem(
      raw: raw ?? this.raw,
      productId: productId,
      businessId: businessId,
      name: name ?? this.name,
      price: price ?? this.price,
      imageUrl: imageUrl ?? this.imageUrl,
      quantity: quantity,
      inStock: inStock ?? this.inStock,
    );
  }
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

  /// An estimate built from the last revalidated public prices. The order
  /// total is whatever the server computes at checkout; this figure is never
  /// treated as authoritative.
  double get subtotal => items.fold(0, (sum, item) => sum + item.total);

  bool get hasUnavailableItem => items.any((item) => !item.inStock);

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
