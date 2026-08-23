import 'package:dio/dio.dart';
import 'package:merzox/services/api_service.dart';

abstract interface class PasswordRecoveryGateway {
  Future<void> requestPasswordReset({required String email});

  Future<void> resetPassword({
    required String token,
    required String newPassword,
  });
}

final class PasswordRecoveryApiService implements PasswordRecoveryGateway {
  final Dio _dio;

  PasswordRecoveryApiService({Dio? dio, String? baseUrl})
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
  Future<void> requestPasswordReset({required String email}) async {
    await _dio.post<Map<String, dynamic>>(
      '/auth/forgot-password',
      data: {'email': email},
    );
  }

  @override
  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '/auth/reset-password',
      data: {'token': token, 'newPassword': newPassword},
    );
  }

  static String messageFromError(Object error) {
    return ApiService.messageFromError(error);
  }
}
