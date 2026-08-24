import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/api_service.dart';
import '../../authentication/bloc/auth_bloc.dart';
import '../cart_item_integrity.dart';
import '../cart_storage_keys.dart';
import '../checkout_failure.dart';
import 'cart_event.dart';
import 'cart_state.dart';

class CartBloc extends Bloc<CartEvent, CartState> {
  final ApiService _apiService;
  final AuthSessionService _authSessionService;

  CartBloc({
    ApiService? apiService,
    AuthSessionService authSessionService = const AuthSessionService(),
  }) : _apiService = apiService ?? ApiService(),
       _authSessionService = authSessionService,
       super(const CartState()) {
    on<CartStarted>(_onStarted);
    on<CartItemRemoved>(_onItemRemoved);
    on<CartCheckoutRequested>(_onCheckoutRequested);
  }

  Future<void> _onStarted(CartStarted event, Emitter<CartState> emit) async {
    emit(state.copyWith(status: CartStatus.loading));
    emit(state.copyWith(status: CartStatus.ready, items: await _loadItems()));
  }

  Future<void> _onItemRemoved(
    CartItemRemoved event,
    Emitter<CartState> emit,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final storedItems = prefs.getStringList(CartStorageKeys.items) ?? [];
    final nextRawItems = [...storedItems]..remove(event.raw);
    await prefs.setStringList(CartStorageKeys.items, nextRawItems);
    await prefs.remove(CartStorageKeys.checkoutId);

    emit(state.copyWith(status: CartStatus.ready, items: await _loadItems()));
  }

  Future<void> _onCheckoutRequested(
    CartCheckoutRequested event,
    Emitter<CartState> emit,
  ) async {
    if (state.items.isEmpty || state.status == CartStatus.checkingOut) return;

    // The cart was revalidated against the public contract when it loaded, so
    // this is a fact we just checked rather than a stale local guess. The
    // server still enforces inventory independently.
    if (state.hasUnavailableItem) {
      emit(
        state.copyWith(
          status: CartStatus.failure,
          errorMessage: 'orders.checkoutOutOfStock',
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        status: CartStatus.checkingOut,
        messageCode: '',
        errorMessage: '',
      ),
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      final session = await _authSessionService.read();
      final token = session.token;
      if (token == null) {
        throw StateError('Authentication required');
      }

      final address = prefs.getString(AuthBloc.addressKey)?.trim() ?? '';
      final groups = <String, List<CartItem>>{};
      for (final item in state.items) {
        groups.putIfAbsent(item.businessId, () => []).add(item);
      }

      var checkoutId = prefs.getString(CartStorageKeys.checkoutId);
      checkoutId ??= 'cart-${DateTime.now().microsecondsSinceEpoch}';
      await prefs.setString(CartStorageKeys.checkoutId, checkoutId);

      var index = 0;
      for (final entry in groups.entries) {
        await _apiService.createOrder(
          token: token,
          businessId: entry.key,
          deliveryAddress: address,
          clientOrderId: '$checkoutId-$index',
          items: entry.value
              .map(
                (item) => OrderItemRequest(
                  productId: item.productId,
                  variantId: item.variantId,
                  quantity: item.quantity,
                ),
              )
              .toList(),
        );
        index += 1;
      }

      await prefs.remove(CartStorageKeys.items);
      await prefs.remove(CartStorageKeys.checkoutId);
      emit(
        state.copyWith(
          status: CartStatus.ready,
          items: const [],
          messageCode: 'orders.checkoutSuccess',
        ),
      );
    } catch (error) {
      // The cart is deliberately NOT cleared and the checkout id is kept, so a
      // retry reuses the same clientOrderId per group: any order that already
      // succeeded is returned as a duplicate instead of being placed twice.
      emit(
        state.copyWith(
          status: CartStatus.failure,
          errorMessage: checkoutFailureMessage(error),
        ),
      );
    }
  }

  Future<List<CartItem>> _loadItems() async {
    final prefs = await SharedPreferences.getInstance();
    final storedItems = prefs.getStringList(CartStorageKeys.items) ?? [];
    final parsedItems = <CartItem>[];

    for (final raw in storedItems) {
      final item = _tryParse(raw);
      if (item == null) continue;

      parsedItems.add(item);
    }

    final refreshedItems = await _revalidate(parsedItems);
    final refreshedRaws = refreshedItems.map((item) => item.raw).toList();

    if (!_sameItems(storedItems, refreshedRaws)) {
      await prefs.setStringList(CartStorageKeys.items, refreshedRaws);
      await prefs.remove(CartStorageKeys.checkoutId);
    }

    return refreshedItems.reversed.toList();
  }

  /// Refreshes each line from the PUBLIC product contract.
  ///
  /// A stored cart entry is a snapshot, and a merchant can change a price or
  /// sell out after it was taken. Rather than presenting that stale snapshot as
  /// if it were current, every line is re-read before the cart is shown, and
  /// the refreshed values are written back so what is displayed and what is
  /// stored cannot disagree.
  ///
  /// A line that cannot be re-read keeps its snapshot untouched: a failed
  /// request is not evidence about price or stock. The backend remains the
  /// checkout authority in every case.
  Future<List<CartItem>> _revalidate(List<CartItem> items) async {
    final refreshed = <CartItem>[];

    for (final item in items) {
      try {
        final product = await _apiService.businessProduct(
          businessId: item.businessId,
          productId: item.productId,
        );

        final name = product.name.isEmpty ? item.name : product.name;
        final imageUrl = product.imageUrl;
        final variantId = item.variantId;

        if (product.hasVariants) {
          // A product that became variant-mode after this cart line was stored
          // cannot choose a variant for the customer.
          if (variantId == null) {
            refreshed.add(
              _identityUnavailable(item, name: name, imageUrl: imageUrl),
            );
            continue;
          }

          BusinessProductVariantApiModel? selectedVariant;

          for (final variant in product.variants) {
            if (variant.id == variantId) {
              selectedVariant = variant;
              break;
            }
          }

          // Removed/inactive variants are absent from the public list. Never
          // substitute a sibling variant with a similar label or price.
          if (selectedVariant == null) {
            refreshed.add(
              _identityUnavailable(item, name: name, imageUrl: imageUrl),
            );
            continue;
          }

          refreshed.add(
            item.copyWith(
              name: name,
              variantLabel: selectedVariant.label,
              price: selectedVariant.finalPrice,
              imageUrl: imageUrl,
              inStock: selectedVariant.inStock,
              raw: _rawFor(
                item,
                name: name,
                variantLabel: selectedVariant.label,
                price: selectedVariant.finalPrice,
                imageUrl: imageUrl,
              ),
            ),
          );
          continue;
        }

        // The inverse identity change is equally unsafe: a line that selected a
        // variant cannot silently degrade into the parent simple product.
        if (variantId != null) {
          refreshed.add(
            _identityUnavailable(item, name: name, imageUrl: imageUrl),
          );
          continue;
        }

        refreshed.add(
          item.copyWith(
            name: name,
            price: product.displayPrice,
            imageUrl: imageUrl,
            inStock: product.inStock,
            raw: _rawFor(
              item,
              name: name,
              price: product.displayPrice,
              imageUrl: imageUrl,
            ),
          ),
        );
      } catch (_) {
        // A failed refresh is not evidence of a stock/identity change. Keep
        // the last known snapshot and let the backend remain checkout authority.
        refreshed.add(item);
      }
    }

    return refreshed;
  }

  CartItem _identityUnavailable(
    CartItem item, {
    required String name,
    required String imageUrl,
  }) {
    return item.copyWith(
      name: name,
      imageUrl: imageUrl,
      inStock: false,
      raw: _rawFor(
        item,
        name: name,
        variantLabel: item.variantLabel,
        price: item.price,
        imageUrl: imageUrl,
      ),
    );
  }

  String _rawFor(
    CartItem item, {
    required String name,
    String? variantLabel,
    required double price,
    required String imageUrl,
  }) {
    final variantId = item.variantId;

    return jsonEncode({
      'businessId': item.businessId,
      'productId': item.productId,
      if (variantId != null) 'variantId': variantId,
      if (variantId != null) 'variantLabel': variantLabel ?? item.variantLabel,
      'name': name,
      'price': price,
      'imageUrl': imageUrl,
      'quantity': item.quantity,
    });
  }

  CartItem? _tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final productId = (decoded['productId'] as String? ?? '').trim();
      final businessId = (decoded['businessId'] as String? ?? '').trim();
      final name = (decoded['name'] as String? ?? '').trim();
      final price = (decoded['price'] as num?)?.toDouble();
      final quantity = (decoded['quantity'] as num?)?.toInt();

      String? variantId;
      final rawVariantId = decoded['variantId'];

      if (rawVariantId != null) {
        if (rawVariantId is! String) return null;

        final normalized = rawVariantId.trim();

        if (normalized.isNotEmpty) {
          if (!isMongoBackedEntityId(normalized)) return null;
          variantId = normalized;
        }
      }

      if (!isMongoBackedEntityId(productId) ||
          !isMongoBackedEntityId(businessId) ||
          name.isEmpty ||
          price == null ||
          !price.isFinite ||
          price < 0 ||
          quantity == null ||
          quantity < 1 ||
          quantity > 100) {
        return null;
      }

      final imageUrl = (decoded['imageUrl'] as String? ?? '').trim();

      final variantLabel = variantId == null
          ? ''
          : (decoded['variantLabel'] as String? ?? '').trim();

      final sanitizedRaw = jsonEncode({
        'businessId': businessId,
        'productId': productId,
        if (variantId != null) 'variantId': variantId,
        if (variantId != null) 'variantLabel': variantLabel,
        'name': name,
        'price': price,
        'imageUrl': imageUrl,
        'quantity': quantity,
      });

      return CartItem(
        raw: sanitizedRaw,
        productId: productId,
        variantId: variantId,
        variantLabel: variantLabel,
        businessId: businessId,
        name: name,
        price: price,
        imageUrl: imageUrl,
        quantity: quantity,
      );
    } catch (_) {
      return null;
    }
  }

  bool _sameItems(List<String> first, List<String> second) {
    if (first.length != second.length) return false;

    for (var index = 0; index < first.length; index += 1) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }
}
