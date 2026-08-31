import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs before every test file in this directory tree.
///
/// The bearer token lives in secure storage, which is a platform channel: with
/// no handler registered a read throws `MissingPluginException`, so every test
/// that installs a session through `SharedPreferences` alone would fail on a
/// plugin rather than on anything it meant to check.
///
/// An empty store is the honest default - signed out - and any test that wants
/// a session installs one over the top, which is what
/// `useAuthenticatedSession` does.
///
/// It is reset before every test rather than once per file, because the mock
/// outlives a test the way a real Keychain would: without this, a test that
/// signs in leaves the next one signed in.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

  await testMain();
}
