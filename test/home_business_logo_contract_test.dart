import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/home/presentation/bloc/home_state_.dart';
import 'package:merzox/services/api_service.dart';

void main() {
  test('business logo URL flows from API payload into HomeBusiness', () {
    const logoUrl = 'https://images.example.test/store-logo.png';

    final response = BusinessListApiResponse.fromJson(<String, dynamic>{
      'businesses': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'business-1',
          'publicId': '0020101',
          'name': 'متجر الياسمين',
          'category': 'متاجر جديدة',
          'logoUrl': logoUrl,
        },
      ],
      'pagination': <String, dynamic>{
        'page': 1,
        'limit': 100,
        'total': 1,
        'hasMore': false,
      },
    });

    final apiBusiness = response.businesses.single;
    final homeBusiness = HomeBusiness.fromApi(apiBusiness);

    expect(apiBusiness.logoUrl, logoUrl);
    expect(homeBusiness.logoUrl, logoUrl);
    expect(homeBusiness.displayId, '0020101');
  });

  test('missing business logo URL remains an empty fallback value', () {
    final apiBusiness = SearchBusinessApiModel.fromJson(<String, dynamic>{
      'id': 'business-without-logo',
      'publicId': '0020102',
      'name': 'متجر بدون شعار',
      'category': 'متاجر جديدة',
    });

    final homeBusiness = HomeBusiness.fromApi(apiBusiness);

    expect(apiBusiness.logoUrl, isEmpty);
    expect(homeBusiness.logoUrl, isEmpty);
  });
}
