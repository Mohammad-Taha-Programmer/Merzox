import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the bearer token lives.
///
/// It used to live in `SharedPreferences` beside the account's display name -
/// a plain XML file on Android and a plist on iOS, readable by anything that
/// can reach the app's directory. The token authenticates every request for
/// seven days and nothing but a password reset can revoke it, so it belongs in
/// the Keystore/Keychain rather than beside the name.
///
/// [read] migrates on first use: a token still sitting in preferences is moved
/// here and erased there, so an account signed in before this existed is not
/// signed out by it.
class SecureTokenStore {
  /// The key inside secure storage. Deliberately not [legacyPreferencesKey]:
  /// the two stores are different places and a shared name would suggest
  /// otherwise.
  static const String key = 'merzox_access_token';

  /// Where the token used to be kept, and where migration reads it from once.
  static const String legacyPreferencesKey = 'auth_access_token';

  final FlutterSecureStorage _storage;

  const SecureTokenStore({FlutterSecureStorage storage = _defaultStorage})
    : _storage = storage;

  /// Android encrypts this with a Keystore-held key; iOS keeps it in the
  /// Keychain, and `first_unlock_this_device` means it is unreadable until the
  /// device has been unlocked once since boot and never leaves it in a backup.
  static const FlutterSecureStorage _defaultStorage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  Future<String?> read() async {
    final String? stored = (await _storage.read(key: key))?.trim();
    if (stored != null && stored.isNotEmpty) {
      return stored;
    }

    return _migrateFromPreferences();
  }

  Future<void> write(String token) async {
    await _storage.write(key: key, value: token);
    // Nothing may be left behind in the old place.
    await _forgetPreferencesCopy();
  }

  Future<void> clear() async {
    await _storage.delete(key: key);
    await _forgetPreferencesCopy();
  }

  /// Moves a token written by an older build, then erases the old copy.
  ///
  /// Returns null when there was nothing to move, which is the ordinary case
  /// for a signed-out account and for every install after the first read.
  Future<String?> _migrateFromPreferences() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? legacy = prefs.getString(legacyPreferencesKey)?.trim();

    if (legacy == null || legacy.isEmpty) {
      await _forgetPreferencesCopy(prefs);
      return null;
    }

    await _storage.write(key: key, value: legacy);
    await prefs.remove(legacyPreferencesKey);

    return legacy;
  }

  Future<void> _forgetPreferencesCopy([SharedPreferences? existing]) async {
    final SharedPreferences prefs =
        existing ?? await SharedPreferences.getInstance();

    if (prefs.containsKey(legacyPreferencesKey)) {
      await prefs.remove(legacyPreferencesKey);
    }
  }
}
