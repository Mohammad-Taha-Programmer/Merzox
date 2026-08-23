import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/services/product_share_service.dart';

void main() {
  const service = ProductShareService();

  test(
    'English product payload contains visible facts and no invented URL',
    () {
      final payload = service.payloadFor(
        productName: '  Test product  ',
        businessName: '  Test business  ',
        displayPrice: 25,
        languageCode: 'en',
      );

      expect(payload.subject, 'Share Test product');
      expect(
        payload.message,
        'Test product\nBusiness: Test business\nPrice: ₪ 25',
      );

      expect(payload.message, isNot(contains('http://')));
      expect(payload.message, isNot(contains('https://')));
      expect(payload.message, isNot(contains('play.google.com')));
      expect(payload.message, isNot(contains('apps.apple.com')));
    },
  );

  test('Arabic payload uses the same visible product facts', () {
    final payload = service.payloadFor(
      productName: 'منتج تجريبي',
      businessName: 'متجر تجريبي',
      displayPrice: 79.6,
      languageCode: 'ar',
    );

    // ProductDetailsPage currently renders displayPrice with zero decimals.
    expect(payload.message, 'منتج تجريبي\nالمتجر: متجر تجريبي\nالسعر: ₪ 80');
  });
}
