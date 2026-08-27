import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/services/recommendation_preference_service.dart';

AuthApiUser _user({required bool permission, Object? consent}) {
  return AuthApiUser.fromJson({
    'id': 'user-1',
    'name': 'Customer',
    'userType': 'normal',
    'permissions': {
      'aiPersonalization': permission,
      'location': false,
      'contacts': false,
    },
    if (consent != null) 'permissionConsents': {'aiPersonalization': consent},
  });
}

void main() {
  test('recommendation preference requires permission and granted consent', () {
    final snapshot = RecommendationPreferenceSnapshot.fromUser(
      _user(
        permission: true,
        consent: {
          'status': 'granted',
          'askedAt': '2026-08-27T09:00:00.000Z',
          'respondedAt': '2026-08-27T09:00:01.000Z',
        },
      ),
    );

    expect(snapshot.enabled, isTrue);
    expect(snapshot.status, 'granted');
  });

  test('permission alone fails closed when consent is missing', () {
    final snapshot = RecommendationPreferenceSnapshot.fromUser(
      _user(permission: true, consent: null),
    );

    expect(snapshot.enabled, isFalse);
    expect(snapshot.status, 'notAsked');
  });

  test('granted consent cannot override disabled permission', () {
    final snapshot = RecommendationPreferenceSnapshot.fromUser(
      _user(permission: false, consent: {'status': 'granted'}),
    );

    expect(snapshot.enabled, isFalse);
    expect(snapshot.status, 'granted');
  });

  test('malformed consent status fails closed to notAsked', () {
    final snapshot = RecommendationPreferenceSnapshot.fromUser(
      _user(permission: true, consent: {'status': 'unexpected'}),
    );

    expect(snapshot.enabled, isFalse);
    expect(snapshot.status, 'notAsked');
  });

  test('explicit denied consent remains disabled', () {
    final snapshot = RecommendationPreferenceSnapshot.fromUser(
      _user(permission: true, consent: {'status': 'denied'}),
    );

    expect(snapshot.enabled, isFalse);
    expect(snapshot.status, 'denied');
  });
}
