import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/secure_token_store.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/cart/bloc/cart_bloc.dart';
import 'package:merzox/features/cart/bloc/cart_event.dart';
import 'package:merzox/features/cart/bloc/cart_state.dart';
import 'package:merzox/features/cart/cart_storage_keys.dart';
import 'package:merzox/features/cart/widgets/cart_items_view.dart';
import 'package:merzox/features/product_details/bloc/product_details_bloc.dart';
import 'package:merzox/features/product_details/bloc/product_details_event.dart';
import 'package:merzox/features/product_details/bloc/product_details_state.dart';
import 'package:merzox/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_test_fixtures.dart';
import 'localization_test_harness.dart';

/// A service is asked for, not counted out.
///
/// A haircut or a delivery is requested once and performed; `3 x haircut` is
/// not a basket a shop can fill. The rule has to hold in three places, because
/// there are three places a number is chosen: the product page, the basket,
/// and the order the server accepts. This file covers the first two; the third
/// is `backend/test/checkout.commerce.test.js`.
const String _businessId = '64b000000000000000000001';
const String _serviceId = '64c000000000000000000009';

class _ServiceApi extends ApiService {
  @override
  Future<BusinessProductApiModel> businessProduct({
    required String businessId,
    required String productId,
  }) async => catalogProduct(id: productId, isService: true);

  @override
  Future<List<BusinessReviewApiModel>> productReviews({
    required String businessId,
    required String productId,
  }) async => const <BusinessReviewApiModel>[];
}

Future<ProductDetailsBloc> _openService() async {
  final ProductDetailsBloc bloc = ProductDetailsBloc(apiService: _ServiceApi());
  addTearDown(bloc.close);

  final Future<ProductDetailsState> ready = bloc.stream.firstWhere(
    (ProductDetailsState state) =>
        state.detailsStatus == ProductDetailsSectionStatus.ready &&
        state.reviewsStatus == ProductDetailsSectionStatus.ready,
  );

  bloc.add(
    ProductDetailsStarted(
      businessId: _businessId,
      initialProduct: catalogProduct(id: _serviceId, isService: true),
    ),
  );
  await ready;

  return bloc;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  setUp(() {
    // Adding to the basket asks for a session first: the flag lives in
    // preferences and the token in secure storage, and both are needed.
    SharedPreferences.setMockInitialValues(<String, Object>{
      AuthBloc.sessionKey: true,
      AuthBloc.userTypeKey: 'normal',
    });
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      SecureTokenStore.key: 'token',
    });
  });

  group('the product page', () {
    test('the number cannot be raised, whatever sends the event', () async {
      // The two buttons are frozen on the screen. This is the same rule at the
      // event, which is reachable without them.
      final ProductDetailsBloc bloc = await _openService();

      bloc.add(const ProductDetailsQuantityIncremented());
      bloc.add(const ProductDetailsQuantityIncremented());
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.quantityIsFixed, isTrue);
      expect(bloc.state.orderQuantity, 1);
    });

    test('an ordinary product is still counted out', () async {
      final ProductDetailsBloc bloc = ProductDetailsBloc(
        apiService: _CountedApi(),
      );
      addTearDown(bloc.close);

      final Future<ProductDetailsState> ready = bloc.stream.firstWhere(
        (ProductDetailsState state) =>
            state.detailsStatus == ProductDetailsSectionStatus.ready,
      );
      bloc.add(
        ProductDetailsStarted(
          businessId: _businessId,
          initialProduct: catalogProduct(),
        ),
      );
      await ready;

      bloc.add(const ProductDetailsQuantityIncremented());
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.quantityIsFixed, isFalse);
      expect(bloc.state.orderQuantity, 2);
    });

    test('the line it writes says it is a service', () async {
      final ProductDetailsBloc bloc = await _openService();

      bloc.add(const ProductDetailsAddToCartPressed());
      await bloc.stream.firstWhere(
        (ProductDetailsState state) => state.message != null,
      );

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> lines =
          prefs.getStringList(CartStorageKeys.items) ?? <String>[];

      expect(lines, hasLength(1));
      final Map<String, dynamic> line =
          jsonDecode(lines.single) as Map<String, dynamic>;
      expect(line['isService'], isTrue);
      expect(line['quantity'], 1);
    });

    test('an ordinary line carries no such flag', () async {
      // Byte for byte the line it was before this flag existed.
      final ProductDetailsBloc bloc = ProductDetailsBloc(
        apiService: _CountedApi(),
      );
      addTearDown(bloc.close);

      final Future<ProductDetailsState> ready = bloc.stream.firstWhere(
        (ProductDetailsState state) =>
            state.detailsStatus == ProductDetailsSectionStatus.ready,
      );
      bloc.add(
        ProductDetailsStarted(
          businessId: _businessId,
          initialProduct: catalogProduct(),
        ),
      );
      await ready;

      bloc.add(const ProductDetailsAddToCartPressed());
      await bloc.stream.firstWhere(
        (ProductDetailsState state) => state.message != null,
      );

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final Map<String, dynamic> line =
          jsonDecode(
                (prefs.getStringList(CartStorageKeys.items) ?? <String>[])
                    .single,
              )
              as Map<String, dynamic>;

      expect(line.containsKey('isService'), isFalse);
    });

    test(
      'asking for the same service twice adds nothing and says so',
      () async {
        // Two lines of one would be summed at checkout into a quantity the
        // server refuses, and the shopper would have no way to see why.
        final ProductDetailsBloc bloc = await _openService();

        bloc.add(const ProductDetailsAddToCartPressed());
        await bloc.stream.firstWhere(
          (ProductDetailsState state) => state.message == 'catalog.addedToCart',
        );

        bloc.add(const ProductDetailsAddToCartPressed());
        final ProductDetailsState second = await bloc.stream.firstWhere(
          (ProductDetailsState state) =>
              state.message == 'catalog.serviceAlreadyInCart',
        );

        expect(second.status, ProductDetailsStatus.action);

        final SharedPreferences prefs = await SharedPreferences.getInstance();
        expect(prefs.getStringList(CartStorageKeys.items), hasLength(1));
      },
    );
  });

  group('the basket', () {
    String serviceLine({int quantity = 1, bool isService = true}) =>
        jsonEncode(<String, dynamic>{
          'businessId': _businessId,
          'productId': _serviceId,
          'name': 'قص شعر',
          'price': 60.0,
          'imageUrl': '',
          'quantity': quantity,
          if (isService) 'isService': true,
        });

    test('a stored service line is read back as one', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        CartStorageKeys.items: <String>[serviceLine()],
      });

      final CartBloc bloc = CartBloc();
      addTearDown(bloc.close);

      bloc.add(const CartStarted());
      final CartState state = await bloc.stream.firstWhere(
        (CartState state) => state.status == CartStatus.ready,
      );

      expect(state.items.single.isService, isTrue);
      expect(state.items.single.quantity, 1);
    });

    test('its number cannot be raised from here either', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        CartStorageKeys.items: <String>[serviceLine()],
      });

      final CartBloc bloc = CartBloc();
      addTearDown(bloc.close);

      bloc.add(const CartStarted());
      final CartState ready = await bloc.stream.firstWhere(
        (CartState state) => state.status == CartStatus.ready,
      );

      bloc.add(
        CartItemQuantityChanged(raw: ready.items.single.raw, quantity: 4),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final Map<String, dynamic> line =
          jsonDecode(
                (prefs.getStringList(CartStorageKeys.items) ?? <String>[])
                    .single,
              )
              as Map<String, dynamic>;

      expect(line['quantity'], 1);
    });

    test('an ordinary line still moves', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        CartStorageKeys.items: <String>[serviceLine(isService: false)],
      });

      final CartBloc bloc = CartBloc();
      addTearDown(bloc.close);

      bloc.add(const CartStarted());
      final CartState ready = await bloc.stream.firstWhere(
        (CartState state) => state.status == CartStatus.ready,
      );

      bloc.add(
        CartItemQuantityChanged(raw: ready.items.single.raw, quantity: 4),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final Map<String, dynamic> line =
          jsonDecode(
                (prefs.getStringList(CartStorageKeys.items) ?? <String>[])
                    .single,
              )
              as Map<String, dynamic>;

      expect(line['quantity'], 4);
    });

    testWidgets('the stepper beside it is frozen', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AuthBloc.sessionKey: true,
        AuthBloc.userTypeKey: 'normal',
        CartStorageKeys.items: <String>[serviceLine()],
      });

      final CartBloc bloc = CartBloc(apiService: _OfflineCartApi())
        ..add(const CartStarted());
      addTearDown(bloc.close);

      await pumpLocalized(
        tester,
        BlocProvider<CartBloc>.value(
          value: bloc,
          child: Scaffold(body: CartItemsView(onContinueShopping: () {})),
        ),
      );
      await settleFrames(tester);

      expect(find.text('قص شعر'), findsOneWidget);

      // Both ends of it. The floor already disables the minus at one, so the
      // plus is what proves the line is frozen rather than merely at its
      // lowest.
      for (final IconData icon in <IconData>[
        Icons.remove_rounded,
        Icons.add_rounded,
      ]) {
        final InkWell button = tester.widget<InkWell>(
          find
              .ancestor(of: find.byIcon(icon), matching: find.byType(InkWell))
              .first,
        );
        expect(button.onTap, isNull, reason: '$icon still answered');

        // And it looks frozen as well as being frozen: the button greys its
        // mark when it has nothing to do.
        expect(
          tester.widget<Icon>(find.byIcon(icon)).color,
          MerzoxColors.kColor8D99AE,
        );
      }
    });
  });
}

class _OfflineCartApi extends ApiService {
  @override
  Future<BusinessProductApiModel> businessProduct({
    required String businessId,
    required String productId,
  }) => throw StateError('offline: the stored line stands');
}

class _CountedApi extends ApiService {
  @override
  Future<BusinessProductApiModel> businessProduct({
    required String businessId,
    required String productId,
  }) async => catalogProduct(id: productId);

  @override
  Future<List<BusinessReviewApiModel>> productReviews({
    required String businessId,
    required String productId,
  }) async => const <BusinessReviewApiModel>[];
}
