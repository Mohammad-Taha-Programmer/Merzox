import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/secure_token_store.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/profile/bloc/profile_edit_bloc.dart';
import 'package:merzox/features/profile/bloc/profile_edit_event.dart';
import 'package:merzox/features/profile/pages/profile_edit_page.dart';
import 'package:merzox/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'localization_test_harness.dart';

/// The account's delivery addresses, on the screen that edits the account.
///
/// They were reachable only from the checkout step before this, which meant a
/// customer could not tidy their addresses except while buying something. The
/// section is built to the shape of the emails and the phones above it, with
/// one difference that is not cosmetic: an address needs a name, a number, a
/// governorate and a city, all four required, so adding one opens the form
/// that collects them rather than a text box that could not.

class _ProfileApi extends ApiService {
  List<SavedAddressApiModel> book;
  final List<String> deleted = <String>[];

  _ProfileApi(this.book);

  @override
  Future<AuthApiUser> me({required String token}) async {
    return AuthApiUser.fromJson(<String, dynamic>{
      'id': 'user-1',
      'name': 'ياسمين خالد',
      'userType': 'normal',
      'gender': 'female',
      'canChangeName': true,
      'canChangeGender': true,
    });
  }

  @override
  Future<List<SavedAddressApiModel>> myAddresses({
    required String token,
  }) async => book;

  @override
  Future<List<SavedAddressApiModel>> deleteAddress({
    required String token,
    required String addressId,
  }) async {
    deleted.add(addressId);
    book = book
        .where((SavedAddressApiModel entry) => entry.id != addressId)
        .toList();
    return book;
  }
}

SavedAddressApiModel _saved({required String id, required String city}) {
  return SavedAddressApiModel.fromJson(<String, dynamic>{
    'id': id,
    'fullName': 'ياسمين خالد',
    'phone': '0599000000',
    'governorate': 'رام الله',
    'city': city,
    'details': 'شارع الإرسال',
  });
}

Future<_ProfileApi> _pumpProfile(
  WidgetTester tester, {
  required List<SavedAddressApiModel> book,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    AuthBloc.sessionKey: true,
    AuthBloc.userTypeKey: 'normal',
  });
  FlutterSecureStorage.setMockInitialValues(<String, String>{
    SecureTokenStore.key: 'token',
  });

  final _ProfileApi api = _ProfileApi(book);
  final ProfileEditBloc bloc = ProfileEditBloc(apiService: api);
  addTearDown(bloc.close);
  bloc.add(const ProfileEditStarted());

  await pumpLocalized(
    tester,
    BlocProvider<ProfileEditBloc>.value(
      value: bloc,
      child: ProfileEditPage(apiService: api),
    ),
  );
  await settleFrames(tester);

  return api;
}

Finder _bins() => find.byIcon(Icons.delete_outline_rounded);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  testWidgets('every saved address is shown as its own line', (tester) async {
    await _pumpProfile(
      tester,
      book: <SavedAddressApiModel>[
        _saved(id: 'a', city: 'البيرة'),
        _saved(id: 'b', city: 'نابلس'),
      ],
    );

    expect(find.text('profileEdit.addresses'.tr()), findsOneWidget);
    // One line each, and the line is what the order would record - not the
    // six fields behind it.
    expect(find.textContaining('البيرة'), findsOneWidget);
    expect(find.textContaining('نابلس'), findsOneWidget);
  });

  testWidgets('an account with none is offered the way to add one', (
    tester,
  ) async {
    await _pumpProfile(tester, book: const <SavedAddressApiModel>[]);

    expect(find.text('profileEdit.addresses'.tr()), findsOneWidget);
    expect(find.text('profileEdit.addAddress'.tr()), findsOneWidget);
  });

  testWidgets('a bin removes one, and the server is told which', (
    tester,
  ) async {
    final _ProfileApi api = await _pumpProfile(
      tester,
      book: <SavedAddressApiModel>[
        _saved(id: 'a', city: 'البيرة'),
        _saved(id: 'b', city: 'نابلس'),
      ],
    );

    // The last bin belongs to the last address: the emails and phones above
    // carry their own, which is the point of counting from the end.
    await tester.tap(_bins().last);
    await settleFrames(tester);

    expect(api.deleted, <String>['b']);
    expect(find.textContaining('نابلس'), findsNothing);
    expect(find.textContaining('البيرة'), findsOneWidget);
  });

  testWidgets('the bin is a bin, on every row that has one', (tester) async {
    // It used to be a red minus in a circle, which reads as a subtraction
    // from a number rather than as removing the line beside it.
    await _pumpProfile(
      tester,
      book: <SavedAddressApiModel>[_saved(id: 'a', city: 'البيرة')],
    );

    expect(find.byIcon(Icons.remove_circle_outline_rounded), findsNothing);
    expect(_bins(), findsWidgets);
  });
}
