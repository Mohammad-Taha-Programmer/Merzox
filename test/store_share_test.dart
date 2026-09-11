import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/business_profile/pages/business_profile_page.dart';
import 'package:merzox/features/home/presentation/bloc/home_state_.dart';
import 'package:merzox/services/store_share_service.dart';

import 'localization_test_harness.dart';

/// Telling somebody about a shop.
///
/// The message has to be findable, which is the difference from sharing a
/// product: a name alone sends the reader looking through a list, and the
/// public id is the one thing that leads back to exactly this shop - which
/// the app already searches by.

class _Recorder implements StoreShareGateway {
  final List<StoreSharePayload> shared = <StoreSharePayload>[];
  final List<String> languages = <String>[];

  @override
  Future<StoreShareOutcome> shareStore({
    required String storeName,
    required String category,
    required String publicId,
    required String languageCode,
    Rect? sharePositionOrigin,
  }) async {
    languages.add(languageCode);
    shared.add(
      const StoreShareService().payloadFor(
        storeName: storeName,
        category: category,
        publicId: publicId,
        languageCode: languageCode,
      ),
    );

    return StoreShareOutcome.selected;
  }
}

HomeBusiness _shop() => HomeBusiness(
  id: 'b1',
  publicId: '93872',
  name: 'البتول كوزماتيكس',
  englishName: 'Al Batoul',
  category: 'مستحضرات تجميل',
  logoUrl: '',
  description: '',
  address: 'أريحا',
  products: const <String>[],
  productCount: 0,
  rating: 0,
  ratingCount: 0,
  followerCount: 0,
  viewCount: 0,
  colorValue: 0xffdeeef8,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  group('what is shared', () {
    test('the name, the kind of shop, and the way back to it', () {
      final StoreSharePayload payload = const StoreShareService().payloadFor(
        storeName: 'البتول كوزماتيكس',
        category: 'مستحضرات تجميل',
        publicId: '93872',
        languageCode: 'ar',
      );

      expect(payload.subject, 'مشاركة البتول كوزماتيكس');
      expect(payload.message, contains('البتول كوزماتيكس'));
      expect(payload.message, contains('مستحضرات تجميل'));
      // The id is the whole point: a name alone sends the reader looking
      // through a list of shops.
      expect(payload.message, contains('93872'));
      expect(payload.message, contains('ابحث'));
    });

    test('and it says the same things in English', () {
      final StoreSharePayload payload = const StoreShareService().payloadFor(
        storeName: 'Al Batoul',
        category: 'Cosmetics',
        publicId: '93872',
        languageCode: 'en',
      );

      expect(payload.subject, 'Share Al Batoul');
      expect(payload.message, contains('Store ID: 93872'));
      expect(payload.message, contains('searching for this ID'));
    });

    test('a shop that filled in nothing leaves the labels out', () {
      // A label with nothing after it reads as a fault rather than as an
      // absence.
      final StoreSharePayload payload = const StoreShareService().payloadFor(
        storeName: 'متجر',
        category: '   ',
        publicId: '',
        languageCode: 'ar',
      );

      expect(payload.message, 'متجر');
      expect(payload.message, isNot(contains('التصنيف')));
      expect(payload.message, isNot(contains('رقم المتجر')));
    });
  });

  group('the button', () {
    testWidgets('is a control, and answers a tap', (WidgetTester tester) async {
      // The storefront itself is not pumped here: it does not settle in a
      // widget test, which is why the product page's slider and its purchase
      // controls were pulled out of it too. What it is made of is checkable.
      int taps = 0;

      await pumpLocalized(
        tester,
        Scaffold(
          body: Center(child: StoreShareButton(onPressed: () => taps += 1)),
        ),
      );

      await tester.tap(find.byKey(const ValueKey<String>('storefront.share')));
      await settleFrames(tester);

      expect(taps, 1);
    });

    testWidgets('hands over the name, the kind, and the id', (
      WidgetTester tester,
    ) async {
      final _Recorder recorder = _Recorder();

      await shareStoreCard(
        gateway: recorder,
        business: _shop(),
        languageCode: 'ar',
      );

      expect(recorder.shared, hasLength(1));
      expect(recorder.shared.single.message, contains('البتول كوزماتيكس'));
      expect(recorder.shared.single.message, contains('مستحضرات تجميل'));
      // The id is what leads back to exactly this shop.
      expect(recorder.shared.single.message, contains('93872'));
      expect(recorder.languages, <String>['ar']);
    });

    test('a shop with no public id falls back to the one it has', () {
      // `displayId` is what the storefront itself prints, so what is shared
      // is what the reader can see and read out.
      final HomeBusiness withoutPublicId = HomeBusiness(
        id: 'b1',
        publicId: '',
        name: 'متجر',
        englishName: '',
        category: '',
        logoUrl: '',
        description: '',
        address: '',
        products: const <String>[],
        productCount: 0,
        rating: 0,
        ratingCount: 0,
        followerCount: 0,
        viewCount: 0,
        colorValue: 0,
      );

      expect(withoutPublicId.displayId, 'b1');
    });
  });
}
