import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/services/api_service.dart';

/// MC001 §17 / AC-21.
///
/// A 2xx response that does not carry the entity its endpoint promises must
/// become a controlled failure. Previously `response.data?['data'] ?? {}` turned
/// a malformed payload into a fully-formed domain object with empty fields, and
/// the UI rendered that as a successful load.
void main() {
  group('requiredEntity', () {
    test('returns the entity when the response is well formed', () {
      final entity = ApiService.requiredEntity(
        const {
          'success': true,
          'data': {
            'order': {'id': '64b000000000000000000001', 'total': 45},
          },
        },
        'order',
        endpoint: 'order',
      );

      expect(entity['id'], '64b000000000000000000001');
      expect(entity['total'], 45);
    });

    test('a missing data envelope is a contract failure', () {
      expect(
        () => ApiService.requiredEntity(
          const {'success': true},
          'order',
          endpoint: 'order',
        ),
        throwsA(isA<ApiContractException>()),
      );
    });

    test('a null body is a contract failure', () {
      expect(
        () => ApiService.requiredEntity(null, 'order', endpoint: 'order'),
        throwsA(isA<ApiContractException>()),
      );
    });

    test('a missing entity key is a contract failure', () {
      expect(
        () => ApiService.requiredEntity(
          const {
            'data': {'somethingElse': 1},
          },
          'order',
          endpoint: 'order',
        ),
        throwsA(isA<ApiContractException>()),
      );
    });

    test('an empty entity object is a contract failure', () {
      // This is the exact shape the old `?? {}` fallback produced.
      expect(
        () => ApiService.requiredEntity(
          const {
            'data': {'order': <String, dynamic>{}},
          },
          'order',
          endpoint: 'order',
        ),
        throwsA(isA<ApiContractException>()),
      );
    });

    test('a non-object entity is a contract failure', () {
      for (final value in [1, 'text', <dynamic>[], true]) {
        expect(
          () => ApiService.requiredEntity(
            {
              'data': {'order': value},
            },
            'order',
            endpoint: 'order',
          ),
          throwsA(isA<ApiContractException>()),
          reason: '$value',
        );
      }
    });

    test('an entity without an id is a contract failure', () {
      for (final id in [null, '', '   ']) {
        expect(
          () => ApiService.requiredEntity(
            {
              'data': {
                'order': {'id': id, 'total': 45},
              },
            },
            'order',
            endpoint: 'order',
          ),
          throwsA(isA<ApiContractException>()),
          reason: 'id=$id',
        );
      }
    });

    test('an id may be waived where the contract does not promise one', () {
      final entity = ApiService.requiredEntity(
        const {
          'data': {
            'summary': {'total': 3},
          },
        },
        'summary',
        endpoint: 'summary',
        requireId: false,
      );

      expect(entity['total'], 3);
    });

    test('the failure names the endpoint without leaking the payload', () {
      try {
        ApiService.requiredEntity(
          const {
            'data': {
              'order': {'id': '', 'customerSecret': 'secret-123'},
            },
          },
          'order',
          endpoint: 'order',
        );
        fail('expected a contract failure');
      } on ApiContractException catch (error) {
        expect(error.endpoint, 'order');
        expect(error.toString().contains('secret-123'), isFalse);
      }
    });
  });

  group('login response contract', () {
    test('a login without a token is refused rather than stored empty', () {
      // AuthSessionService would reject an empty token later, but failing at
      // the parse keeps the reason visible instead of a silent logout.
      for (final body in [
        const {
          'data': {
            'user': {'id': 'u1'},
          },
        },
        const {
          'data': {
            'token': '',
            'user': {'id': 'u1'},
          },
        },
        const {
          'data': {
            'token': '   ',
            'user': {'id': 'u1'},
          },
        },
      ]) {
        expect(
          () => AuthApiResponse.fromJson(body),
          throwsA(isA<ApiContractException>()),
        );
      }
    });

    // AC-21 closure: an authenticated response must carry the identity it
    // authenticates. Each case below previously produced a usable
    // AuthApiResponse holding an id-less AuthApiUser.
    test('CASE A: a valid token with no data.user is refused', () {
      expect(
        () => AuthApiResponse.fromJson(const {
          'data': {'token': 'real-token'},
        }),
        throwsA(isA<ApiContractException>()),
      );
    });

    test('CASE B: a valid token with a non-object user is refused', () {
      for (final user in [1, 'text', <dynamic>[], true]) {
        expect(
          () => AuthApiResponse.fromJson({
            'data': {'token': 'real-token', 'user': user},
          }),
          throwsA(isA<ApiContractException>()),
          reason: '$user',
        );
      }
    });

    test('CASE C: a valid token with a user missing an id is refused', () {
      for (final user in [
        <String, dynamic>{},
        {'name': 'Mohammad'},
        {'id': '', 'name': 'Mohammad'},
        {'id': '   ', 'name': 'Mohammad'},
      ]) {
        expect(
          () => AuthApiResponse.fromJson({
            'data': {'token': 'real-token', 'user': user},
          }),
          throwsA(isA<ApiContractException>()),
          reason: '$user',
        );
      }
    });

    test('no malformed auth response yields a usable session', () {
      // The decisive property: none of the malformed shapes can produce an
      // AuthApiResponse at all, so no token reaches session persistence.
      final malformed = <Map<String, dynamic>>[
        const {'data': <String, dynamic>{}},
        const {
          'data': {'token': 'real-token'},
        },
        const {
          'data': {
            'token': '',
            'user': {'id': 'u1'},
          },
        },
        const {
          'data': {
            'token': 'real-token',
            'user': {'id': ''},
          },
        },
      ];

      for (final body in malformed) {
        AuthApiResponse? parsed;
        try {
          parsed = AuthApiResponse.fromJson(body);
        } on ApiContractException {
          parsed = null;
        }
        expect(parsed, isNull, reason: '$body');
      }
    });

    test('CASE E: a real login response parses and keeps the token', () {
      final auth = AuthApiResponse.fromJson(const {
        'data': {
          'token': 'real-token',
          'user': {
            'id': 'u1',
            'name': 'Mohammad',
            'userType': 'normal',
            'gender': 'unspecified',
            'address': '',
          },
        },
      });

      expect(auth.token, 'real-token');
      expect(auth.user.name, 'Mohammad');
    });
  });

  group('error message mapping', () {
    test('contract failures map to a stable localization key', () {
      final message = ApiService.messageFromError(
        const ApiContractException('order', 'response has no "order" object'),
      );

      expect(message, 'apiErrors.contract');
      expect(message.contains('ApiContractException'), isFalse);
      expect(message.contains('order'), isFalse);
    });

    test('connection failures map to a stable localization key', () {
      final message = ApiService.messageFromError(
        DioException(
          requestOptions: RequestOptions(path: '/health'),
          type: DioExceptionType.connectionError,
        ),
      );

      expect(message, 'apiErrors.connection');
    });

    test('unexpected failures map to a stable localization key', () {
      expect(
        ApiService.messageFromError(StateError('boom')),
        'apiErrors.unexpected',
      );
    });

    test('backend-provided error messages remain raw', () {
      final request = RequestOptions(path: '/orders');

      final message = ApiService.messageFromError(
        DioException(
          requestOptions: request,
          response: Response<Map<String, dynamic>>(
            requestOptions: request,
            statusCode: 400,
            data: const {
              'error': {'message': 'Server says no. Please retry.'},
            },
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      expect(message, 'Server says no. Please retry.');
    });
  });
}
