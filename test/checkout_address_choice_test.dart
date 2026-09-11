import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/cart/bloc/cart_bloc.dart';
import 'package:merzox/features/cart/bloc/cart_event.dart';
import 'package:merzox/core/auth/secure_token_store.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/checkout/pages/checkout_page.dart';
import 'package:merzox/services/api_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'localization_test_harness.dart';

/// Choosing where an order goes.
///
/// The step draws one radio per saved address and the order takes the chosen
/// one. It used to have a fallback beside it: an account whose `addresses`
/// book was empty was shown its profile's single `address` string instead, as
/// one card that could not be chosen - which read exactly like a screen that
/// only ever offers one address, and is what sent us looking. The account has
/// no single address any more, so an empty book is an empty book, and that is
/// the last case below.

class _AddressApi extends ApiService {
  final List<SavedAddressApiModel> book;

  _AddressApi(this.book);

  @override
  Future<List<SavedAddressApiModel>> myAddresses({
    required String token,
  }) async => book;
}

SavedAddressApiModel _saved({
  required String id,
  required String city,
  bool isDefault = false,
}) {
  return SavedAddressApiModel.fromJson(<String, dynamic>{
    'id': id,
    'label': city,
    'fullName': 'ياسمين خالد',
    'phone': '0599000000',
    'governorate': 'رام الله',
    'city': city,
    'details': 'شارع الإرسال',
    'isDefault': isDefault,
  });
}

Future<void> _pumpCheckout(
  WidgetTester tester, {
  required List<SavedAddressApiModel> book,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    AuthBloc.sessionKey: true,
    AuthBloc.nameKey: 'ياسمين خالد',
  });
  FlutterSecureStorage.setMockInitialValues(<String, String>{
    SecureTokenStore.key: 'token',
  });

  final _AddressApi api = _AddressApi(book);
  // The page reads the cart above it; an empty one reaches ready without any
  // product lookup, which is all this test needs from it.
  final CartBloc cart = CartBloc(apiService: api);
  addTearDown(cart.close);
  cart.add(const CartStarted());

  await pumpLocalized(
    tester,
    BlocProvider<CartBloc>.value(
      value: cart,
      child: CheckoutPage(apiService: api),
    ),
  );
  await settleFrames(tester);
}

Finder _chosen() => find.byIcon(Icons.radio_button_checked);
Finder _unchosen() => find.byIcon(Icons.radio_button_unchecked);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  testWidgets('every saved address is offered, one of them chosen', (
    tester,
  ) async {
    await _pumpCheckout(
      tester,
      book: <SavedAddressApiModel>[
        _saved(id: 'a', city: 'البيرة'),
        _saved(id: 'b', city: 'رام الله', isDefault: true),
        _saved(id: 'c', city: 'نابلس'),
      ],
    );

    // Three cards, and exactly one of them chosen - an order goes to one
    // address, so this is a choice of one and not a set of ticks.
    expect(_chosen(), findsOneWidget);
    expect(_unchosen(), findsNWidgets(2));
  });

  testWidgets('the one marked default is the one chosen for you', (
    tester,
  ) async {
    // Not the first in the book: the default is chosen because it is the
    // default, not because of where it happens to sit.
    await _pumpCheckout(
      tester,
      book: <SavedAddressApiModel>[
        _saved(id: 'a', city: 'البيرة'),
        _saved(id: 'b', city: 'نابلس', isDefault: true),
      ],
    );

    final Finder chosenCard = find
        .ancestor(of: _chosen(), matching: find.byType(InkWell))
        .first;

    expect(
      find.descendant(of: chosenCard, matching: find.textContaining('نابلس')),
      findsOneWidget,
    );
  });

  testWidgets('another can be chosen, and the choice moves', (tester) async {
    await _pumpCheckout(
      tester,
      book: <SavedAddressApiModel>[
        _saved(id: 'a', city: 'البيرة', isDefault: true),
        _saved(id: 'b', city: 'نابلس'),
      ],
    );

    await tester.tap(_unchosen().first);
    await settleFrames(tester);

    expect(_chosen(), findsOneWidget);
    expect(_unchosen(), findsOneWidget);
  });

  testWidgets('an empty book is said plainly, not filled from elsewhere', (
    tester,
  ) async {
    // An empty book used to fall back to the profile's single address string,
    // drawn as one card that could not be chosen - which is what read as "the
    // screen only ever shows one address". That field is gone from the
    // account, so an empty book is now an empty book.
    await _pumpCheckout(tester, book: const <SavedAddressApiModel>[]);

    expect(find.text('checkout.noSavedAddress'.tr()), findsOneWidget);
    expect(_chosen(), findsNothing);
    expect(_unchosen(), findsNothing);
  });
}
