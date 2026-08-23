import 'package:dio/dio.dart';
import 'package:merzox/services/api_service.dart';

final class NotificationPreferenceSnapshot {
  final bool productOffers;

  const NotificationPreferenceSnapshot({required this.productOffers});
}

abstract interface class NotificationPreferenceGateway {
  Future<NotificationPreferenceSnapshot> load({required String token});

  Future<NotificationPreferenceSnapshot> update({
    required String token,
    required bool productOffers,
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
    required bool productOffers,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/users/me/notification-preferences',
      data: {'productOffers': productOffers},
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

    return NotificationPreferenceSnapshot(productOffers: productOffers);
  }
}
