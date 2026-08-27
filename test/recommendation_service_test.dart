import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/services/recommendation_service.dart';

AuthApiUser user(bool permission, String status) => AuthApiUser.fromJson({
  'id': 'u1',
  'name': 'User',
  'userType': 'normal',
  'permissions': {'aiPersonalization': permission},
  'permissionConsents': {
    'aiPersonalization': {'status': status},
  },
});

RecommendationApiResponse response() => RecommendationApiResponse.fromJson({
  'consent': {'enabled': true, 'status': 'granted'},
  'personalized': true,
  'preferenceCategories': ['Food'],
  'recommendations': [
    {'id': 'b1', 'publicId': 'B1', 'name': 'Food Store', 'category': 'Food'},
  ],
});

void main() {
  test('denied consent performs zero catalog reads', () async {
    var reads = 0;

    final service = RecommendationService(
      userLoader: ({required token}) async => user(true, 'denied'),
      catalogLoader: ({required token}) async {
        reads += 1;
        return response();
      },
    );

    final result = await service.load(token: 'token');

    expect(result.consentEnabled, isFalse);
    expect(reads, 0);
  });

  test('permission false performs zero catalog reads', () async {
    var reads = 0;

    final service = RecommendationService(
      userLoader: ({required token}) async => user(false, 'granted'),
      catalogLoader: ({required token}) async {
        reads += 1;
        return response();
      },
    );

    final result = await service.load(token: 'token');

    expect(result.consentEnabled, isFalse);
    expect(reads, 0);
  });

  test('granted consent returns recommendations', () async {
    final service = RecommendationService(
      userLoader: ({required token}) async => user(true, 'granted'),
      catalogLoader: ({required token}) async => response(),
    );

    final result = await service.load(token: 'token');

    expect(result.consentEnabled, isTrue);
    expect(result.personalized, isTrue);
    expect(result.businesses.single.id, 'b1');
  });
}
