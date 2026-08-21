import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/api_service.dart';
import '../../authentication/bloc/auth_bloc.dart';
import '../cart_storage_keys.dart';
import 'cart_event.dart';
import 'cart_state.dart';

class CartBloc extends Bloc<CartEvent, CartState> {
  final ApiService _apiService;

  CartBloc({ApiService? apiService})
    : _apiService = apiService ?? ApiService(),
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

    emit(
      state.copyWith(
        status: CartStatus.checkingOut,
        messageCode: '',
        errorMessage: '',
      ),
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(AuthBloc.tokenKey);
      if (token == null || token.isEmpty) {
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
                  quantity: item.quantity,
                  variant: item.degree,
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
    } catch (_) {
      emit(
        state.copyWith(
          status: CartStatus.failure,
          errorMessage: 'orders.checkoutError',
        ),
      );
    }
  }

  Future<List<CartItem>> _loadItems() async {
    final prefs = await SharedPreferences.getInstance();
    final storedItems = prefs.getStringList(CartStorageKeys.items) ?? [];

    return storedItems
        .map(_tryParse)
        .whereType<CartItem>()
        .toList()
        .reversed
        .toList();
  }

  CartItem? _tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      return CartItem(
        raw: raw,
        productId: decoded['productId'] as String? ?? '',
        businessId: decoded['businessId'] as String? ?? '',
        name: decoded['name'] as String? ?? 'المنتج',
        price: (decoded['price'] as num?)?.toDouble() ?? 0,
        imageUrl: decoded['imageUrl'] as String? ?? '',
        quantity: (decoded['quantity'] as num?)?.toInt() ?? 1,
        degree: decoded['degree'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}
