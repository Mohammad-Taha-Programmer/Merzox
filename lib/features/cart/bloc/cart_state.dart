enum CartStatus { initial, loading, ready, checkingOut, failure }

final class CartItem {
  final String raw;
  final String productId;

  /// Null means the parent/simple product itself is the sellable identity.
  /// Present means this cart line is bound to that exact server variant.
  final String? variantId;

  /// Display snapshot only. It never proves variant identity to the backend.
  final String variantLabel;

  final String businessId;
  final String name;

  /// Server-derived payable price as of the last successful revalidation.
  /// Display only - checkout reprices from the exact sellable identity.
  final double price;

  final String imageUrl;
  final int quantity;

  /// Availability of this exact sellable identity after revalidation.
  final bool inStock;

  const CartItem({
    required this.raw,
    required this.productId,
    required this.businessId,
    required this.name,
    required this.price,
    required this.imageUrl,
    required this.quantity,
    this.variantId,
    this.variantLabel = '',
    this.inStock = true,
  });

  bool get hasVariant => variantId != null;

  double get total => price * quantity;

  CartItem copyWith({
    String? raw,
    String? variantLabel,
    String? name,
    double? price,
    String? imageUrl,
    bool? inStock,
  }) {
    return CartItem(
      raw: raw ?? this.raw,
      productId: productId,
      variantId: variantId,
      variantLabel: variantLabel ?? this.variantLabel,
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

  /// Estimate only. The backend computes authoritative checkout totals.
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
