import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/services/api_service.dart';

/// One number field on an account, and where the singular answer comes from.
///
/// There were two: a `phones` list and a `phone` string holding a copy of its
/// first entry, written in the same breath by every path that touched either.
/// The string is gone from the wire and from the database; what is left is a
/// list, and a reading of it for the places that need one number.
AuthApiUser _account(List<Map<String, dynamic>> phones) =>
    AuthApiUser.fromJson(<String, dynamic>{
      'id': 'u1',
      'name': 'ياسمين',
      'userType': 'normal',
      'phones': phones,
    });

void main() {
  test('the account with no number has none', () {
    expect(_account(<Map<String, dynamic>>[]).phone, isNull);
  });

  test('one number is the number', () {
    final AuthApiUser account = _account(<Map<String, dynamic>>[
      <String, dynamic>{'value': '+970592029316', 'label': 'mobile'},
    ]);

    expect(account.phone, '+970592029316');
  });

  test('the one marked primary is the one, wherever it sits in the list', () {
    final AuthApiUser account = _account(<Map<String, dynamic>>[
      <String, dynamic>{'value': '+970592029316', 'label': 'work'},
      <String, dynamic>{
        'value': '+970599000000',
        'label': 'mobile',
        'isPrimary': true,
      },
    ]);

    expect(account.phone, '+970599000000');
  });

  test('with none marked, the first stands for the account', () {
    final AuthApiUser account = _account(<Map<String, dynamic>>[
      <String, dynamic>{'value': '+970592029316', 'label': 'work'},
      <String, dynamic>{'value': '+970599000000', 'label': 'home'},
    ]);

    expect(account.phone, '+970592029316');
  });

  // The server no longer sends one, and an old response that still did would
  // be a second source of the same fact - which is the arrangement this
  // change removed.
  test('a phone arriving on the wire is not read', () {
    final AuthApiUser account = AuthApiUser.fromJson(<String, dynamic>{
      'id': 'u1',
      'name': 'ياسمين',
      'userType': 'normal',
      'phone': '+970111111111',
      'phones': <Map<String, dynamic>>[
        <String, dynamic>{'value': '+970592029316', 'label': 'mobile'},
      ],
    });

    expect(account.phone, '+970592029316');
    expect(account.phones.single.value, '+970592029316');
  });
}
