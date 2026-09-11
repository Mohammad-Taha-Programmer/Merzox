import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every picture the code asks for has to be one the bundle actually carries.
///
/// `- assets/images/` in `pubspec.yaml` is not recursive. A subfolder left out
/// of the list resolves in the editor, survives `flutter analyze`, and throws
/// the first time a screen asks for a picture inside it - which in a release
/// is a customer looking at a broken screen with no warning anywhere before
/// it. It has happened twice: the follow button's faces and the empty cart's
/// drawing, each caught by a test that was looking at something else.
///
/// The rule checked here is what actually has to hold: an asset path written
/// in `lib/` must name a file that exists, in a folder the pubspec declares.
/// It is deliberately not "every folder must be declared" - a picture parked
/// under `assets/images/` for work not started yet is not a fault, and making
/// the bundle carry it to satisfy a test would be one.
void main() {
  late List<String> referenced;
  late String pubspec;

  setUpAll(() {
    pubspec = File('pubspec.yaml').readAsStringSync();

    // Any 'assets/...' string literal in the app's own source.
    final RegExp literal = RegExp(r"'(assets/[\w./ -]+\.\w+)'");
    final Set<String> found = <String>{};
    for (final FileSystemEntity entity in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      for (final RegExpMatch m in literal.allMatches(
        entity.readAsStringSync(),
      )) {
        found.add(m.group(1)!);
      }
    }
    referenced = found.toList()..sort();
  });

  test('every asset the code names is on disk', () {
    expect(referenced, isNotEmpty, reason: 'no asset paths were found in lib/');

    for (final String path in referenced) {
      expect(
        File(path).existsSync(),
        isTrue,
        reason: '$path is written in lib/ and is not there',
      );
    }
  });

  test('every asset the code names sits in a declared folder', () {
    for (final String path in referenced) {
      final String folder = '${path.substring(0, path.lastIndexOf('/'))}/';

      // Fonts are declared one file at a time under `fonts:`, pictures a
      // folder at a time under `assets:`, so either form counts.
      final bool declared =
          pubspec.contains('- $folder') || pubspec.contains(path);

      expect(
        declared,
        isTrue,
        reason:
            '$path is drawn by the app and pubspec.yaml declares neither it '
            'nor $folder, so it throws at runtime and nothing says so first',
      );
    }
  });
}
