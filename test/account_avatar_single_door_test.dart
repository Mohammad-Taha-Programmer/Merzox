import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/authentication/account_avatar.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One door to the account's picture, and this is what keeps it the only one.
///
/// Storage is where the URL lives; `AccountAvatar` is what tells the running
/// app it changed. A write that goes straight to storage stores the picture
/// perfectly and announces nothing, so whichever screen did the writing
/// repaints and every other screen that draws the same picture does not.
///
/// That is not a hypothetical. It is the exact shape of the fault this was
/// written for, and then of the one left behind when three of the four writers
/// were moved across and the fourth - the profile tab's own upload - was
/// missed. The reader set a picture, saw it on the tab they set it on, and did
/// not see it in the top bar.
///
/// Reading is not restricted: knowing what is stored harms nothing. Writing is.
const String _key = 'avatarUrlKey';

/// Where the picture is allowed to be written.
const String _door = 'lib/features/authentication/account_avatar.dart';

/// A write to shared preferences, whatever the key looks like at the call.
final RegExp _write = RegExp(r'(setString|remove)\(\s*[^)]*' + _key);

void main() {
  test('only AccountAvatar writes the stored picture', () {
    final List<String> offenders = <String>[];

    for (final FileSystemEntity entity in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final String path = entity.path.replaceAll(r'\', '/');
      if (path.endsWith(_door)) continue;

      final String source = entity.readAsStringSync();
      if (_write.hasMatch(source)) offenders.add(path);
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'these write the account picture straight to storage instead of '
          'through AccountAvatar, so every other screen that draws it is '
          'never told: ${offenders.join(', ')}',
    );
  });

  // The guard above is worth nothing if the key it looks for is not the key
  // the app uses, so the two are tied together here rather than trusted to
  // stay the same by eye.
  test('the guard is watching the key the app actually stores under', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AccountAvatar.remember('https://pictures.example/face.png');

    final SharedPreferences prefs = await SharedPreferences.getInstance();

    expect(
      prefs.getString(AuthBloc.avatarUrlKey),
      'https://pictures.example/face.png',
    );
    expect(
      File(_door).readAsStringSync(),
      contains('AuthBloc.$_key'),
      reason: 'the door no longer writes under the name the guard scans for',
    );
  });
}
