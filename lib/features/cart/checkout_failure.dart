import 'package:dio/dio.dart';

/// Turns a checkout failure into the localization key that tells the customer
/// what actually happened.
///
/// The server owns inventory and pricing, so its refusal codes are the only
/// honest source for these messages. Collapsing every failure into one generic
/// "checkout error" would hide the difference between "this sold out" and "the
/// request never arrived", which the customer needs in order to act.
const Map<String, String> checkoutFailureMessages = {
  'PRODUCT_OUT_OF_STOCK': 'orders.checkoutOutOfStock',
  'INSUFFICIENT_STOCK': 'orders.checkoutInsufficientStock',
  'PRODUCT_NOT_AVAILABLE': 'orders.checkoutProductUnavailable',
  'PRODUCT_VARIANT_REQUIRED': 'catalog.selectVariant',
  'PRODUCT_VARIANT_NOT_AVAILABLE': 'catalog.variantUnavailable',
  'BUSINESS_NOT_FOUND': 'orders.checkoutBusinessUnavailable',
  'DELIVERY_ADDRESS_REQUIRED': 'orders.checkoutAddressRequired',
};

/// The generic fallback, used only when the server named no reason we model.
const String checkoutFailureFallback = 'orders.checkoutError';

String checkoutFailureMessage(Object? error) {
  return checkoutFailureMessages[checkoutFailureCode(error)] ??
      checkoutFailureFallback;
}

/// Reads the stable error code out of an API failure, without ever surfacing
/// a raw server message to the UI.
String? checkoutFailureCode(Object? error) {
  if (error is! DioException) return null;

  final body = error.response?.data;
  if (body is! Map) return null;

  final nested = body['error'];
  final code = nested is Map ? nested['code'] : body['code'];

  return code is String && code.isNotEmpty ? code : null;
}
