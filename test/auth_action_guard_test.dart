import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_gate.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/cart/cart_storage_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('guest cannot execute any protected action or alter the cart', () async {
    const existingCartItem = '{"productId":"existing-product"}';
    SharedPreferences.setMockInitialValues({
      AuthBloc.sessionKey: false,
      CartStorageKeys.items: [existingCartItem],
    });
    const guard = AuthActionGuard();
    var addToCartDispatched = false;
    var createOrderCalled = false;
    var reviewSubmitted = false;
    var optimisticLikeApplied = false;

    final results = await Future.wait([
      guard.run(() => addToCartDispatched = true),
      guard.run(() => createOrderCalled = true),
      guard.run(() => reviewSubmitted = true),
      guard.run(() => optimisticLikeApplied = true),
    ]);

    expect(results, everyElement(isFalse));
    expect(addToCartDispatched, isFalse);
    expect(createOrderCalled, isFalse);
    expect(reviewSubmitted, isFalse);
    expect(optimisticLikeApplied, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(CartStorageKeys.items), [existingCartItem]);
  });

  test('authenticated user can execute a protected action', () async {
    SharedPreferences.setMockInitialValues({
      AuthBloc.sessionKey: true,
      AuthBloc.tokenKey: 'customer-token',
      AuthBloc.userTypeKey: 'normal',
    });
    const guard = AuthActionGuard();
    var executed = false;

    final allowed = await guard.run(() => executed = true);

    expect(allowed, isTrue);
    expect(executed, isTrue);
  });
}
