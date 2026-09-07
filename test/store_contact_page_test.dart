import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/business/contact/store_contact_channels.dart';
import 'package:merzox/features/business/contact/store_contact_page.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/services/api_service.dart';

import 'localization_test_harness.dart';

/// How a shop can be reached, gathered in one place.
///
/// The values are whatever the merchant typed - a handle, a pasted link, a
/// number with or without a country code - so the work is turning each into
/// something a phone can actually open, and refusing the ones that are not.
///
/// The row that leads here used to push `/about`, which is not a route: the
/// section did nothing but show an error screen.

OwnerBusiness _shop({BusinessSocialLinks? links}) {
  return OwnerBusiness.fromJson(<String, dynamic>{
    'id': 'b1',
    'name': 'البتول كوزماتيكس',
    'category': 'Cosmetics',
    'logoUrl': '',
    'socialLinks': <String, dynamic>{
      'instagram': links?.instagram ?? '',
      'whatsapp': links?.whatsapp ?? '',
      'facebook': links?.facebook ?? '',
    },
  });
}

AuthApiUser _account({
  List<String> phones = const <String>[],
  List<String> emails = const <String>[],
}) {
  return AuthApiUser.fromJson(<String, dynamic>{
    'id': 'u1',
    'name': 'بتول طه',
    'userType': 'business',
    'phones': <Map<String, dynamic>>[
      for (final String phone in phones)
        <String, dynamic>{'value': phone, 'label': 'mobile'},
    ],
    'emails': <Map<String, dynamic>>[
      for (final String email in emails)
        <String, dynamic>{'value': email, 'label': 'work'},
    ],
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  group('turning what was typed into somewhere to go', () {
    test('a number becomes a call, and WhatsApp its own address', () {
      expect(telUri('+970 562-000000').toString(), 'tel:+970562000000');
      expect(telUri('0562000000').toString(), 'tel:0562000000');

      // `wa.me` wants digits alone: a `+` in the path is read as part of the
      // number and the chat opens on nobody.
      expect(whatsappUri('+970562000000').toString(), 'https://wa.me/970562000000');

      expect(telUri('   '), isNull);
      expect(telUri('no digits here'), isNull);
      expect(whatsappUri(''), isNull);
    });

    test('an address becomes a message', () {
      expect(mailtoUri(' b@taha.com ').toString(), 'mailto:b@taha.com');
      expect(mailtoUri('not an address'), isNull);
      expect(mailtoUri(''), isNull);
    });

    test('a handle is hung off the site, and a link is left alone', () {
      // What a merchant means when they type their name into a field
      // labelled Instagram.
      expect(
        socialUri('albatoul', host: 'instagram.com').toString(),
        'https://instagram.com/albatoul',
      );
      expect(
        socialUri('@albatoul', host: 'instagram.com').toString(),
        'https://instagram.com/albatoul',
      );
      expect(
        socialUri('https://instagram.com/albatoul', host: 'instagram.com')
            .toString(),
        'https://instagram.com/albatoul',
      );
    });

    test('anything that is neither is refused rather than pasted on a host', () {
      // A `javascript:` string hung off instagram.com would be a link to
      // nowhere at best.
      for (final String value in <String>[
        '',
        '   ',
        'javascript:alert(1)',
        'some one',
        'path/with/slashes',
        'ftp://host/x',
      ]) {
        expect(
          socialUri(value, host: 'instagram.com'),
          isNull,
          reason: '$value should not become a link',
        );
      }
    });
  });

  group('what the page offers', () {
    testWidgets('a row for each channel that was actually filled in', (
      WidgetTester tester,
    ) async {
      await pumpLocalized(
        tester,
        StoreContactPage(
          business: _shop(
            links: const BusinessSocialLinks(
              whatsapp: '+970562000000',
              instagram: 'albatoul',
            ),
          ),
          account: _account(
            phones: <String>['+970562000000'],
            emails: <String>['b@taha.com'],
          ),
          open: (Uri _) async => true,
        ),
      );

      expect(
        find.byKey(const ValueKey<String>('storeContact.whatsapp')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('storeContact.instagram')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('storeContact.phone')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('storeContact.email')),
        findsOneWidget,
      );

      // Facebook was never filled in, and a row that led nowhere would be
      // worse than a shorter page.
      expect(
        find.byKey(const ValueKey<String>('storeContact.facebook')),
        findsNothing,
      );
    });

    testWidgets('a tap opens exactly where the value points', (
      WidgetTester tester,
    ) async {
      final List<Uri> opened = <Uri>[];

      await pumpLocalized(
        tester,
        StoreContactPage(
          business: _shop(
            links: const BusinessSocialLinks(whatsapp: '+970562000000'),
          ),
          account: _account(),
          open: (Uri uri) async {
            opened.add(uri);
            return true;
          },
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('storeContact.whatsapp')),
      );
      await settleFrames(tester);

      expect(opened.map((Uri uri) => uri.toString()), <String>[
        'https://wa.me/970562000000',
      ]);
    });

    testWidgets('a device that cannot open it says so', (
      WidgetTester tester,
    ) async {
      // A phone with no WhatsApp answers no rather than throwing, and silence
      // there would look like a dead row.
      await pumpLocalized(
        tester,
        StoreContactPage(
          business: _shop(
            links: const BusinessSocialLinks(whatsapp: '+970562000000'),
          ),
          account: _account(),
          open: (Uri _) async => false,
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('storeContact.whatsapp')),
      );
      await settleFrames(tester);

      expect(find.text('تعذر فتح هذه الوسيلة على جهازك.'), findsOneWidget);
    });

    testWidgets('a shop that gave nothing is told where to give it', (
      WidgetTester tester,
    ) async {
      bool wentToSettings = false;

      await pumpLocalized(
        tester,
        StoreContactPage(
          business: _shop(),
          account: _account(),
          open: (Uri _) async => true,
          onEditSettings: () => wentToSettings = true,
        ),
      );

      expect(find.textContaining('لم تُضِف بعد'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('storeContact.openSettings')),
      );
      await settleFrames(tester);

      expect(wentToSettings, isTrue);
    });

    testWidgets('the way back is the board chevron', (
      WidgetTester tester,
    ) async {
      await pumpLocalized(
        tester,
        StoreContactPage(
          business: _shop(),
          account: _account(),
          open: (Uri _) async => true,
        ),
      );

      final Icon icon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey<String>('storeContact.back')),
          matching: find.byType(Icon),
        ),
      );

      expect(icon.icon, Icons.chevron_left_rounded);
      expect(icon.icon!.matchTextDirection, isTrue);
    });
  });

  group('an account from before the lists existed', () {
    test('its single number and address are still offered', () {
      // Older accounts carry `phone` and `email` alone, and a page that read
      // only the lists would show nothing for them.
      final AuthApiUser legacy = AuthApiUser.fromJson(<String, dynamic>{
        'id': 'u1',
        'name': 'بتول طه',
        'userType': 'business',
        'phone': '+970562000000',
        'email': 'b@taha.com',
      });

      expect(storePhoneChannels(legacy).single.label, '+970562000000');
      expect(storeEmailChannels(legacy).single.label, 'b@taha.com');
    });

    test('and no account at all offers nothing rather than throwing', () {
      expect(storePhoneChannels(null), isEmpty);
      expect(storeEmailChannels(null), isEmpty);
    });
  });
}
