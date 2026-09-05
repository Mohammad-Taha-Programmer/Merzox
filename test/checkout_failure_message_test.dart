import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/localization/api_error_localizer.dart';
import 'package:merzox/features/cart/checkout_failure.dart';

/// What a customer reads when an order will not go through.
///
/// This map decides that, and nothing tested it. It cost a real defect: the
/// server refused every order because the client sent `deliveryOption` and the
/// allowlist omitted it, and because `INVALID_ORDER_FIELDS` was unmapped the
/// customer was told to check their address and their products - both of which
/// were fine.

DioException _refusal(String code) {
  return DioException(
    requestOptions: RequestOptions(path: '/orders'),
    response: Response<Map<String, dynamic>>(
      requestOptions: RequestOptions(path: '/orders'),
      statusCode: 400,
      data: <String, dynamic>{
        'success': false,
        'error': <String, dynamic>{'code': code, 'message': 'refused'},
      },
    ),
  );
}

void main() {
  test('every refusal the map models names its own reason', () {
    const Map<String, String> expected = <String, String>{
      'PRODUCT_OUT_OF_STOCK': 'orders.checkoutOutOfStock',
      'INSUFFICIENT_STOCK': 'orders.checkoutInsufficientStock',
      'PRODUCT_NOT_AVAILABLE': 'orders.checkoutProductUnavailable',
      'PRODUCT_VARIANT_REQUIRED': 'catalog.selectVariant',
      'PRODUCT_VARIANT_NOT_AVAILABLE': 'catalog.variantUnavailable',
      'BUSINESS_NOT_FOUND': 'orders.checkoutBusinessUnavailable',
      'DELIVERY_ADDRESS_REQUIRED': 'orders.checkoutAddressRequired',
      'INVALID_ORDER_FIELDS': 'orders.checkoutRejectedShape',
    };

    for (final MapEntry<String, String> entry in expected.entries) {
      expect(
        checkoutFailureMessage(_refusal(entry.key)),
        entry.value,
        reason: '${entry.key} must not fall through to the generic message',
      );
    }
  });

  test('a refused request shape does not blame the address', () {
    final String message = checkoutFailureMessage(
      _refusal('INVALID_ORDER_FIELDS'),
    );

    expect(message, isNot(checkoutFailureFallback));
    expect(message, isNot('orders.checkoutAddressRequired'));
  });

  test('a code nobody models still says something', () {
    expect(
      checkoutFailureMessage(_refusal('SOME_CODE_ADDED_LATER')),
      checkoutFailureFallback,
    );
  });

  test('a failure that is not the server speaking falls back too', () {
    expect(
      checkoutFailureMessage(StateError('offline')),
      checkoutFailureFallback,
    );
    expect(checkoutFailureMessage(null), checkoutFailureFallback);
    expect(
      checkoutFailureMessage(
        DioException(requestOptions: RequestOptions(path: '/orders')),
      ),
      checkoutFailureFallback,
    );
  });

  test('the code is read from either envelope shape', () {
    expect(
      checkoutFailureCode(_refusal('PRODUCT_OUT_OF_STOCK')),
      'PRODUCT_OUT_OF_STOCK',
    );

    final DioException flat = DioException(
      requestOptions: RequestOptions(path: '/orders'),
      response: Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/orders'),
        statusCode: 400,
        data: const <String, dynamic>{'code': 'INSUFFICIENT_STOCK'},
      ),
    );

    expect(checkoutFailureCode(flat), 'INSUFFICIENT_STOCK');
  });

  test('these keys are not the kind `localizeApiErrorOrRaw` can translate', () {
    // That helper translates only keys under `apiErrors.` and returns
    // everything else untouched. The cart tab ran failures through it, so a
    // refused order showed the customer the literal text
    // `orders.checkoutOutOfStock`. Both screens call `.tr()` now, and this
    // records why reaching for the helper here would be wrong again.
    for (final String key in <String>{
      ...checkoutFailureMessages.values,
      checkoutFailureFallback,
    }) {
      expect(
        localizeApiErrorOrRaw(key),
        key,
        reason: '$key would be shown raw',
      );
      expect(key.startsWith(apiErrorLocalizationPrefix), isFalse);
    }
  });

  test('every message this map points at exists in both languages', () async {
    final Iterable<String> keys = <String>{
      ...checkoutFailureMessages.values,
      checkoutFailureFallback,
    };

    for (final String locale in <String>['ar', 'en']) {
      final Map<String, dynamic> catalogue =
          jsonDecode(
                await File('assets/translations/$locale.json').readAsString(),
              )
              as Map<String, dynamic>;

      for (final String key in keys) {
        final List<String> parts = key.split('.');
        final Map<String, dynamic>? section =
            catalogue[parts.first] as Map<String, dynamic>?;

        expect(
          section?[parts.last],
          isA<String>(),
          reason: '$locale is missing $key',
        );
      }
    }
  });
}
