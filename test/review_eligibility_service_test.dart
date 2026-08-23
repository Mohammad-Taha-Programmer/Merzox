import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/services/review_eligibility_service.dart';

void main() {
  test(
    'review eligibility API uses exact authenticated GET contracts',
    () async {
      final requests = <RequestOptions>[];

      final dio = Dio(BaseOptions(baseUrl: 'http://example.test/api/v1'));

      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: const {
                  'success': true,
                  'data': {
                    'eligibility': {'eligible': true, 'reason': null},
                  },
                },
              ),
            );
          },
        ),
      );

      final service = ReviewEligibilityService(dio: dio);

      final business = await service.businessEligibility(
        token: 'customer-token',
        businessId: 'business-1',
      );

      final product = await service.productEligibility(
        token: 'customer-token',
        businessId: 'business-1',
        productId: 'product-7',
      );

      expect(business.eligible, isTrue);
      expect(product.eligible, isTrue);

      expect(requests, hasLength(2));

      expect(requests[0].method, 'GET');
      expect(requests[0].path, '/businesses/business-1/review-eligibility');
      expect(requests[0].headers['Authorization'], 'Bearer customer-token');
      expect(requests[0].data, isNull);

      expect(requests[1].method, 'GET');
      expect(
        requests[1].path,
        '/businesses/business-1/products/product-7/review-eligibility',
      );
      expect(requests[1].headers['Authorization'], 'Bearer customer-token');
      expect(requests[1].data, isNull);
    },
  );

  test('server ineligibility reason is parsed exactly', () async {
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
                  'eligibility': {
                    'eligible': false,
                    'reason': 'deliveredPurchaseRequired',
                  },
                },
              },
            ),
          );
        },
      ),
    );

    final result = await ReviewEligibilityService(
      dio: dio,
    ).businessEligibility(token: 'customer-token', businessId: 'business-1');

    expect(result.eligible, isFalse);
    expect(result.reason, ReviewEligibilityReason.deliveredPurchaseRequired);
  });

  test('malformed eligibility payload fails closed', () async {
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
                  'eligibility': {
                    'eligible': true,
                    'reason': 'deliveredPurchaseRequired',
                  },
                },
              },
            ),
          );
        },
      ),
    );

    expect(
      () => ReviewEligibilityService(
        dio: dio,
      ).businessEligibility(token: 'customer-token', businessId: 'business-1'),
      throwsA(isA<ApiContractException>()),
    );
  });
}
