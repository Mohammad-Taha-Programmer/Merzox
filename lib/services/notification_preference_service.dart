import 'package:dio/dio.dart';
import 'package:merzox/services/api_service.dart';

/// The names the server knows. Anything else it refuses.
final class NotificationPreferenceKeys {
  const NotificationPreferenceKeys._();

  /// The customer's marketing switch.
  static const String productOffers = 'productOffers';

  /// The merchant's, which `البروفايل` puts at the foot of its menu. Separate
  /// from the customer's so silencing marketing cannot silence the notice
  /// that an order arrived.
  static const String orderUpdates = 'orderUpdates';
}

final class NotificationPreferenceSnapshot {
  final bool productOffers;
  final bool orderUpdates;

  const NotificationPreferenceSnapshot({
    required this.productOffers,
    this.orderUpdates = true,
  });

  /// The value of one preference by name.
  bool valueOf(String key) => key == NotificationPreferenceKeys.orderUpdates
      ? orderUpdates
      : productOffers;
}

abstract interface class NotificationPreferenceGateway {
  Future<NotificationPreferenceSnapshot> load({required String token});

  /// [key] names which preference is being set; the server refuses a body
  /// carrying more than one.
  Future<NotificationPreferenceSnapshot> update({
    required String token,
    required bool value,
    String key = NotificationPreferenceKeys.productOffers,
  });
}

final class NotificationPreferenceService
    implements NotificationPreferenceGateway {
  final Dio _dio;

  NotificationPreferenceService({Dio? dio, String? baseUrl})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl ?? ApiService.defaultBaseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
              headers: const {'Content-Type': 'application/json'},
            ),
          );

  @override
  Future<NotificationPreferenceSnapshot> load({required String token}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/users/me/notification-preferences',
      options: _authOptions(token),
    );

    return _parse(response.data);
  }

  @override
  Future<NotificationPreferenceSnapshot> update({
    required String token,
    required bool value,
    String key = NotificationPreferenceKeys.productOffers,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/users/me/notification-preferences',
      data: <String, dynamic>{key: value},
      options: _authOptions(token),
    );

    return _parse(response.data);
  }

  Options _authOptions(String token) {
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  NotificationPreferenceSnapshot _parse(Map<String, dynamic>? response) {
    final data = response?['data'];

    if (data is! Map<String, dynamic>) {
      throw const ApiContractException(
        'notificationPreferences',
        'response did not contain data',
      );
    }

    final rawPreferences = data['notificationPreferences'];

    if (rawPreferences is! Map<String, dynamic>) {
      throw const ApiContractException(
        'notificationPreferences',
        'response did not contain notificationPreferences',
      );
    }

    final productOffers = rawPreferences['productOffers'];

    if (productOffers is! bool) {
      throw const ApiContractException(
        'notificationPreferences',
        'notificationPreferences.productOffers must be boolean',
      );
    }

    // Tolerated when absent: a server that predates this key is still a
    // server whose customer preference the app must respect.
    final orderUpdates = rawPreferences['orderUpdates'];

    if (orderUpdates != null && orderUpdates is! bool) {
      throw const ApiContractException(
        'notificationPreferences',
        'notificationPreferences.orderUpdates must be boolean',
      );
    }

    return NotificationPreferenceSnapshot(
      productOffers: productOffers,
      orderUpdates: orderUpdates as bool? ?? true,
    );
  }
}
