import 'package:flutter/foundation.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the account's picture is, for everything in the running app that
/// draws it.
///
/// Storage is where the URL persists; this is how the rest of the app finds
/// out it has changed. That distinction is the whole reason this exists: the
/// picture is drawn in two places - the home screen's top bar and the profile
/// tab - which are two tabs of one screen, so a URL the profile tab wrote to
/// storage was not news to the bar until something unrelated happened to
/// rebuild it. A reader who added a picture saw it on the tab they added it
/// on and nowhere else.
///
/// Everything that changes the picture goes through here, so that storage and
/// the screens can no longer hold different answers.
final class AccountAvatar {
  const AccountAvatar._();

  static final ValueNotifier<String> _url = ValueNotifier<String>('');

  /// The picture as it stands. Empty means the account has none and the
  /// figure is drawn instead.
  static ValueListenable<String> get url => _url;

  /// What storage holds, at startup.
  static Future<void> restore() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _url.value = prefs.getString(AuthBloc.avatarUrlKey)?.trim() ?? '';
  }

  /// A picture, stored and announced in one step.
  static Future<void> remember(String url) async {
    final String trimmed = url.trim();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(AuthBloc.avatarUrlKey, trimmed);
    _url.value = trimmed;
  }

  /// Signing out. The picture goes with the session rather than outliving it
  /// in storage, where the next account's first frame would have drawn it.
  static Future<void> forget() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(AuthBloc.avatarUrlKey);
    _url.value = '';
  }
}
