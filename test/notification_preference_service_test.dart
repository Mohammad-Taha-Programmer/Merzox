import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/services/notification_preference_service.dart';

void main() {
  test('preference service uses exact authenticated GET and PATCH', () async {
    final requests = <RequestOptions>[];

    final dio = Dio(BaseOptions(baseUrl: 'http://example.test/api/v1'));

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);

          final value = options.method == 'GET';

          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'success': true,
                'data': {
                  'notificationPreferences': {'productOffers': value},
                },
              },
            ),
          );
        },
      ),
    );

    final service = NotificationPreferenceService(dio: dio);

    final loaded = await service.load(token: 'token-1');
    final updated = await service.update(
      token: 'token-1',
      productOffers: false,
    );

    expect(loaded.productOffers, isTrue);
    expect(updated.productOffers, isFalse);

    expect(requests, hasLength(2));

    expect(requests[0].method, 'GET');
    expect(requests[0].path, '/users/me/notification-preferences');
    expect(requests[0].headers['Authorization'], 'Bearer token-1');
    expect(requests[0].data, isNull);

    expect(requests[1].method, 'PATCH');
    expect(requests[1].path, '/users/me/notification-preferences');
    expect(requests[1].headers['Authorization'], 'Bearer token-1');
    expect(requests[1].data, {'productOffers': false});
  });

  test('explicit server false remains false', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://example.test/api/v1'));

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: const {
                'success': true,
                'data': {
                  'notificationPreferences': {'productOffers': false},
                },
              },
            ),
          );
        },
      ),
    );

    final result = await NotificationPreferenceService(
      dio: dio,
    ).load(token: 'token');

    expect(result.productOffers, isFalse);
  });

  test('malformed preference payload fails closed', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://example.test/api/v1'));

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: const {
                'success': true,
                'data': {
                  'notificationPreferences': {'productOffers': 'true'},
                },
              },
            ),
          );
        },
      ),
    );

    expect(
      () => NotificationPreferenceService(dio: dio).load(token: 'token'),
      throwsA(isA<ApiContractException>()),
    );
  });
}
