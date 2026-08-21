import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/cart/bloc/cart_bloc.dart';
import 'package:merzox/features/cart/bloc/cart_event.dart';
import 'package:merzox/features/cart/bloc/cart_state.dart';
import 'package:merzox/features/cart/cart_storage_keys.dart';
import 'package:merzox/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailIfOrderCreatedApi extends ApiService {
  int createOrderCalls = 0;

  @override
  Future<OrderApiModel> createOrder({
    required String token,
    required String businessId,
    required List<OrderItemRequest> items,
    required String deliveryAddress,
    String paymentMethod = 'cash',
    String? clientOrderId,
  }) async {
    createOrderCalls += 1;
    throw StateError('Synthetic cart data reached checkout');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'cart migration keeps real IDs and removes legacy synthetic entries',
    () async {
      final real = jsonEncode({
        'businessId': '64b000000000000000000001',
        'productId': '64c000000000000000000001',
        'name': 'Real product',
        'price': 25,
        'imageUrl': '',
        'quantity': 2,
        'degree': '02',
      });
      final legacy = jsonEncode({
        'businessId': '0020101',
        'productId': 'local-new-0',
        'name': 'Legacy product',
        'price': 35,
        'quantity': 1,
      });
      SharedPreferences.setMockInitialValues({
        CartStorageKeys.items: [legacy, real],
        CartStorageKeys.checkoutId: 'old-checkout',
      });
      final bloc = CartBloc();
      addTearDown(bloc.close);

      final stateFuture = bloc.stream.firstWhere(
        (state) => state.status == CartStatus.ready,
      );
      bloc.add(const CartStarted());
      final state = await stateFuture;

      expect(state.items, hasLength(1));
      expect(state.items.single.name, 'Real product');
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(CartStorageKeys.items)!;
      expect(stored, hasLength(1));
      final sanitized = jsonDecode(stored.single) as Map<String, dynamic>;
      expect(sanitized['businessId'], '64b000000000000000000001');
      expect(sanitized['productId'], '64c000000000000000000001');
      expect(sanitized.containsKey('degree'), isFalse);
      expect(prefs.getString(CartStorageKeys.checkoutId), isNull);
    },
  );

  test('legacy-only cart never reaches order creation', () async {
    final legacy = jsonEncode({
      'businessId': '0020101',
      'productId': 'local-new-0',
      'name': 'Legacy product',
      'price': 35,
      'quantity': 1,
    });
    SharedPreferences.setMockInitialValues({
      AuthBloc.sessionKey: true,
      AuthBloc.tokenKey: 'customer-token',
      AuthBloc.userTypeKey: 'normal',
      CartStorageKeys.items: [legacy],
    });
    final api = _FailIfOrderCreatedApi();
    final bloc = CartBloc(apiService: api);
    addTearDown(bloc.close);

    final stateFuture = bloc.stream.firstWhere(
      (state) => state.status == CartStatus.ready,
    );
    bloc.add(const CartStarted());
    final state = await stateFuture;
    expect(state.items, isEmpty);

    bloc.add(const CartCheckoutRequested());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(api.createOrderCalls, 0);
  });
}
