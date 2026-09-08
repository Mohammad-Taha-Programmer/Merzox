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

  // The same options every one of the app's API clients is built
  // with. They all reach the one server, so a timeout raised for a
  // slow network has to reach all of them or it fixes one screen.
  PasswordRecoveryApiService({Dio? dio, String? baseUrl, Duration? timeout})
    : _dio =
          dio ??
          Dio(ApiService.options(baseUrl: baseUrl, timeout: timeout));

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
