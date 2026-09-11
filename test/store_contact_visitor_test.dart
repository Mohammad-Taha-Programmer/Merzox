import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/business/contact/store_contact_page.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/features/business/settings/store_settings_page.dart';
import 'package:merzox/features/business/shell/business_bloc.dart';
import 'package:merzox/features/business_profile/pages/business_profile_page.dart';
import 'package:merzox/services/api_service.dart';

import 'auth_session_fixtures.dart';
import 'localization_test_harness.dart';

/// Records what store settings would send, without a server behind it.
class _SettingsApi extends ApiService {
  final List<Map<String, dynamic>> saved = <Map<String, dynamic>>[];

  @override
  Future<OwnerBusiness> updateOwnerBusiness({
    required String token,
    required Map<String, dynamic> changes,
  }) async {
    saved.add(changes);

    return OwnerBusiness.fromJson(<String, dynamic>{
      'id': 'b1',
      'name': 'متجر الاختبار',
      'category': 'Groceries',
      'showOwnerContact': changes['showOwnerContact'],
    });
  }
}

/// A customer reading how to reach somebody else's shop.
///
/// The same screen the merchant sees, from a different source. The merchant
/// reads their own account; a customer reads what the server chose to publish
/// - and what it publishes of an owner's own number and address depends on a
/// permission that starts off. So most of what is checked here is what does
/// NOT travel.

BusinessDetailApiModel _detail({
  Map<String, dynamic> socialLinks = const <String, dynamic>{},
  Map<String, dynamic> contact = const <String, dynamic>{},
}) {
  return BusinessDetailApiModel.fromJson(<String, dynamic>{
    'id': 'b1',
    'publicId': '93872',
    'name': 'البتول كوزماتيكس',
    'category': 'مستحضرات تجميل',
    'description': '',
    'address': 'أريحا',
    'logoUrl': '',
    'products': const <dynamic>[],
    'socialLinks': socialLinks,
    'contact': contact,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  group('what the storefront was told', () {
    test('the links and the published numbers are read off the detail', () {
      final BusinessDetailApiModel detail = _detail(
        socialLinks: const <String, dynamic>{
          'whatsapp': '+970562000000',
          'instagram': 'albatoul',
          'facebook': '',
        },
        contact: const <String, dynamic>{
          'phones': <Map<String, dynamic>>[
            <String, dynamic>{'value': '+970562000000', 'label': 'mobile'},
          ],
          'emails': <Map<String, dynamic>>[
            <String, dynamic>{'value': 'b@taha.com', 'label': 'work'},
          ],
        },
      );

      expect(detail.socialLinks.whatsapp, '+970562000000');
      expect(detail.socialLinks.instagram, 'albatoul');
      expect(detail.contact.phones.single.value, '+970562000000');
      expect(detail.contact.emails.single.value, 'b@taha.com');
    });

    test('a response with no contact block is a shop that said nothing', () {
      // An older server, or a truncated payload. Neither may read as a shop
      // that gave permission it never gave.
      final BusinessDetailApiModel detail = _detail();

      expect(detail.contact.isEmpty, isTrue);
      expect(detail.socialLinks.isEmpty, isTrue);
    });
  });

  group('whether there is a way in at all', () {
    test('a shop that published nothing gets no row', () {
      // A row that opened an empty page would be the dead end the contact
      // screen itself refuses to draw a row for.
      expect(visitorContactPage(_detail()), isNull);
    });

    test('a storefront with no detail yet gets no row', () {
      expect(visitorContactPage(null), isNull);
    });

    test('links alone are enough, with no permission given', () {
      final StoreContactPage? page = visitorContactPage(
        _detail(socialLinks: const <String, dynamic>{'instagram': 'albatoul'}),
      );

      expect(page, isNotNull);
      expect(page!.social, hasLength(1));
      // The owner said nothing about their own number, so there is none here.
      expect(page.phones, isEmpty);
      expect(page.emails, isEmpty);
    });

    test('a permission that was given brings the account through', () {
      final StoreContactPage? page = visitorContactPage(
        _detail(
          contact: const <String, dynamic>{
            'phones': <Map<String, dynamic>>[
              <String, dynamic>{'value': '+970562000000', 'label': 'mobile'},
            ],
          },
        ),
      );

      expect(page, isNotNull);
      expect(page!.phones.single.uri.toString(), 'tel:+970562000000');
    });
  });

  group('what the page shows a visitor', () {
    testWidgets('the channels the shop published, and nothing to edit', (
      WidgetTester tester,
    ) async {
      final List<Uri> opened = <Uri>[];

      await pumpLocalized(
        tester,
        StoreContactPage.forVisitor(
          storeName: 'البتول كوزماتيكس',
          category: 'مستحضرات تجميل',
          logoUrl: '',
          socialLinks: _detail(
            socialLinks: const <String, dynamic>{'whatsapp': '+970562000000'},
          ).socialLinks,
          contact: _detail(
            contact: const <String, dynamic>{
              'emails': <Map<String, dynamic>>[
                <String, dynamic>{'value': 'b@taha.com', 'label': 'work'},
              ],
            },
          ).contact,
          open: (Uri uri) async {
            opened.add(uri);
            return true;
          },
        ),
      );

      expect(find.text('البتول كوزماتيكس'), findsOneWidget);
      expect(find.text('+970562000000'), findsOneWidget);
      expect(find.text('b@taha.com'), findsOneWidget);

      // The merchant's way back to store settings has no meaning here: a
      // customer cannot fill in somebody else's shop.
      expect(
        find.byKey(const ValueKey<String>('storeContact.openSettings')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('storeContact.whatsapp')),
      );
      await settleFrames(tester);

      expect(opened.single.toString(), 'https://wa.me/970562000000');
    });

    testWidgets('an empty page speaks to the reader who is actually there', (
      WidgetTester tester,
    ) async {
      await pumpLocalized(
        tester,
        StoreContactPage.forVisitor(
          storeName: 'متجر',
          category: '',
          logoUrl: '',
          socialLinks: _detail().socialLinks,
          contact: _detail().contact,
        ),
      );

      // The merchant is told what to add. A customer is told the shop has not
      // said - the same absence, but only one of them can do anything.
      expect(find.text('storeContact.emptyForVisitor'.tr()), findsOneWidget);
      expect(find.text('storeContact.empty'.tr()), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('storeContact.openSettings')),
        findsNothing,
      );
    });
  });

  group('the permission behind the numbers', () {
    test('a payload that lost the field is not permission', () {
      // An older server, or a response that came back short. Neither may be
      // read as a yes the merchant never gave.
      final OwnerBusiness shop = OwnerBusiness.fromJson(<String, dynamic>{
        'id': 'b1',
        'name': 'متجر',
        'category': 'Groceries',
      });

      expect(shop.showOwnerContact, isFalse);
    });

    testWidgets('store settings starts it off and sends what was chosen', (
      WidgetTester tester,
    ) async {
      useAuthenticatedSession(business: true);

      final _SettingsApi api = _SettingsApi();
      final BusinessBloc bloc = BusinessBloc(apiService: api);
      addTearDown(bloc.close);

      await pumpLocalized(
        tester,
        BlocProvider<BusinessBloc>.value(
          value: bloc,
          child: StoreSettingsPage(
            business: OwnerBusiness.fromJson(<String, dynamic>{
              'id': 'b1',
              'name': 'متجر الاختبار',
              'category': 'Groceries',
            }),
            apiService: api,
          ),
        ),
      );

      await tester.tap(find.text('storeSettings.socialLinks'.tr()));
      await settleFrames(tester);

      final Finder permission = find.byKey(
        const ValueKey<String>('storeSettings.showOwnerContact'),
      );
      expect(permission, findsOneWidget);
      expect(tester.widget<SwitchListTile>(permission).value, isFalse);

      await tester.tap(permission);
      await settleFrames(tester);
      await tester.tap(find.text('common.save'.tr()));
      await settleFrames(tester);

      // The switch is the whole of what the merchant decides here. The
      // numbers themselves are the account's, and store settings never sends
      // a copy of them.
      expect(api.saved.single['showOwnerContact'], isTrue);
      expect(api.saved.single.containsKey('phones'), isFalse);
      expect(api.saved.single.containsKey('emails'), isFalse);
    });
  });

  group('the circle that leads there', () {
    testWidgets('is a control, and answers a tap', (WidgetTester tester) async {
      // The storefront itself is not pumped: it does not settle in a widget
      // test, which is why its share button is exercised on its own too.
      int taps = 0;

      await pumpLocalized(
        tester,
        Scaffold(
          body: Center(child: StoreContactButton(onPressed: () => taps += 1)),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('storefront.contact')),
      );
      await settleFrames(tester);

      expect(taps, 1);
    });
  });
}
