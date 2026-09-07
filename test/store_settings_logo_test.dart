import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/features/business/settings/store_settings_page.dart';
import 'package:merzox/features/business/settings/widgets/store_logo_field.dart';
import 'package:merzox/features/business/shell/business_bloc.dart';
import 'package:merzox/services/api_service.dart';

import 'auth_session_fixtures.dart';
import 'localization_test_harness.dart';

/// The logo section of the store settings screen.
///
/// It used to be a picture beside a box you pasted a link into, and a line
/// telling a shopkeeper their file had to be under half a megabyte. The box is
/// gone - the picture is chosen now, from a camera, a gallery or a link - and
/// so is the demand, because the app brings the picture down itself.

final Uint8List _bytes = Uint8List.fromList(<int>[9, 9, 9]);

class _LogoApi extends ApiService {
  final List<Uint8List> uploaded = <Uint8List>[];

  String url = 'https://images.test/stored.png';

  @override
  Future<AuthApiUser> uploadMyAvatar({
    required String token,
    required Uint8List bytes,
  }) async {
    uploaded.add(bytes);

    return AuthApiUser.fromJson(<String, dynamic>{
      'id': 'u1',
      'name': 'بتول طه',
      'avatarUrl': url,
    });
  }
}

OwnerBusiness _shop({String logoUrl = ''}) {
  return OwnerBusiness.fromJson(<String, dynamic>{
    'id': 'b1',
    'name': 'متجر الاختبار',
    'category': 'Groceries',
    'logoUrl': logoUrl,
  });
}

Future<void> _openLogoSection(
  WidgetTester tester, {
  required _LogoApi api,
  StoreLogoDevicePicker? picker,
  String logoUrl = '',
}) async {
  final BusinessBloc bloc = BusinessBloc(apiService: api);
  addTearDown(bloc.close);

  await pumpLocalized(
    tester,
    BlocProvider<BusinessBloc>.value(
      value: bloc,
      child: StoreSettingsPage(
        business: _shop(logoUrl: logoUrl),
        apiService: api,
        logoDevicePicker: picker,
      ),
    ),
  );

  await tester.tap(find.text('شعار المتجر'));
  await settleFrames(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  setUp(() => useAuthenticatedSession(business: true));

  testWidgets('the section offers the picture itself, not a link box', (
    WidgetTester tester,
  ) async {
    await _openLogoSection(tester, api: _LogoApi());

    expect(find.byType(StoreLogoField), findsOneWidget);
    // The box that asked for a URL is gone: a link is now one of the three
    // ways in, behind the picture, rather than a field of its own.
    expect(find.text('قم بإرفاق رابط شعار المتجر'), findsNothing);
  });

  testWidgets('a shop with no logo shows the board\'s empty box', (
    WidgetTester tester,
  ) async {
    await _openLogoSection(tester, api: _LogoApi());

    expect(
      find.byKey(const ValueKey<String>('storeLogo.placeholder')),
      findsOneWidget,
    );
  });

  testWidgets('the caption asks for a shape, and no longer for a file size', (
    WidgetTester tester,
  ) async {
    // Knowing whether a photograph is under half a megabyte is not something
    // a shopkeeper should have to find out, and it was the only part of that
    // line they could fail.
    await _openLogoSection(tester, api: _LogoApi());

    expect(find.textContaining('99'), findsOneWidget);
    expect(find.textContaining('ميجا'), findsNothing);
  });

  testWidgets('the social section asks for no phone number of its own', (
    WidgetTester tester,
  ) async {
    // The number a shop would print is its owner's, and the account holds it
    // already - given at sign-up, corrected in the personal profile. A box
    // here asked for it a third time and kept a third copy.
    await _openLogoSection(tester, api: _LogoApi());

    await tester.tap(find.text('وسائل التواصل الاجتماعي'));
    await settleFrames(tester);

    expect(find.text('قم بإدخال رقم الواتس مع المقدمة'), findsOneWidget);
    expect(find.byIcon(Icons.phone_outlined), findsNothing);
  });

  testWidgets('a chosen picture is stored, and the box shows it', (
    WidgetTester tester,
  ) async {
    final _LogoApi api = _LogoApi();

    await _openLogoSection(
      tester,
      api: api,
      picker: (StoreLogoSource _) async => _bytes,
    );

    await tester.tap(find.byKey(const ValueKey<String>('storeLogo.box')));
    await settleFrames(tester);
    await tester.tap(find.byKey(const ValueKey<String>('storeLogo.gallery')));
    await settleFrames(tester);

    // Stored the moment it is chosen, by the account picture endpoint: a
    // merchant has one picture, and the server puts it on the shop they own.
    expect(api.uploaded, <Uint8List>[_bytes]);

    final StoreLogoField field = tester.widget<StoreLogoField>(
      find.byType(StoreLogoField),
    );
    expect(field.logoUrl, 'https://images.test/stored.png');
  });
}
