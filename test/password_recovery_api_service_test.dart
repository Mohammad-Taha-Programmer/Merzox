import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/authentication/password_recovery/data/password_recovery_api_service.dart';

void main() {
  test('recovery API sends the exact public auth contracts', () async {
    final requests = <RequestOptions>[];

    final dio = Dio(BaseOptions(baseUrl: 'http://example.test/api/v1'));

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: options.path.endsWith('/forgot-password') ? 202 : 200,
              data: const {'success': true, 'data': <String, dynamic>{}},
            ),
          );
        },
      ),
    );

    final service = PasswordRecoveryApiService(dio: dio);

    await service.requestPasswordReset(email: 'owner@example.com');

    await service.resetPassword(token: 'A' * 43, newPassword: 'new-secret');

    expect(requests, hasLength(2));

    expect(requests[0].method, 'POST');
    expect(requests[0].path, '/auth/forgot-password');
    expect(requests[0].data, {'email': 'owner@example.com'});

    expect(requests[1].method, 'POST');
    expect(requests[1].path, '/auth/reset-password');
    expect(requests[1].data, {'token': 'A' * 43, 'newPassword': 'new-secret'});
  });
}
