import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'golden/merzox_golden_harness.dart';

/// The shape of `assets/fonts/icons_fonts/`, which is now a rule and not a
/// habit.
///
/// Every screen that draws one of the designer's marks owns its own copy of
/// it, in a folder named for that screen, under a family named for the same
/// thing. The point is that replacing one screen's star replaces exactly one
/// screen's star.
///
/// Three lists have to agree for that to hold: the files on disk, the families
/// in `pubspec.yaml`, and the families the golden harness loads. Nothing makes
/// them agree on its own, and each disagreement fails somewhere different and
/// late:
///
///  * a family declared with no file behind it draws the engine's empty box on
///    a phone, and nothing says so at build time;
///  * a file nobody declares is dead weight in the bundle;
///  * a family the harness does not load draws that same empty box in a
///    capture, which reads as an icon that was never drawn rather than a font
///    that was never loaded - a mistake this project has already made once.
///
/// `not_yet_used/` is exempt and is the one place a file may sit undeclared:
/// it holds drawings the designer supplied that no screen has a use for yet.
void main() {
  const String root = 'assets/fonts/icons_fonts';
  const String parking = '$root/not_yet_used';

  late List<String> files;
  late Set<String> declared;
  late Map<String, String> declaredAsset;

  setUpAll(() {
    files =
        Directory(root)
            .listSync(recursive: true)
            .whereType<File>()
            .map((File f) => f.path.replaceAll(r'\', '/'))
            .where((String p) => p.endsWith('.ttf'))
            .toList()
          ..sort();

    final String pubspec = File('pubspec.yaml').readAsStringSync();
    declared = <String>{};
    declaredAsset = <String, String>{};

    // `- family: X` followed by its one asset line, which is how every glyph
    // font in this project is declared.
    final RegExp pattern = RegExp(
      r'- family: (\w+)\s*\n\s*fonts:\s*\n\s*- asset: >?-?\s*'
      r'([\w./ -]+\.ttf)',
      multiLine: true,
    );
    for (final RegExpMatch m in pattern.allMatches(pubspec)) {
      final String asset = m.group(2)!.trim();
      if (!asset.startsWith(root)) continue;
      declared.add(m.group(1)!);
      declaredAsset[m.group(1)!] = asset;
    }
  });

  test('every declared family has a file behind it', () {
    expect(declared, isNotEmpty, reason: 'nothing was parsed out of pubspec');

    for (final MapEntry<String, String> entry in declaredAsset.entries) {
      expect(
        File(entry.value).existsSync(),
        isTrue,
        reason: '${entry.key} is declared and ${entry.value} is not there',
      );
    }
  });

  test('every file is declared, except the ones with no screen yet', () {
    for (final String path in files) {
      if (path.startsWith(parking)) continue;
      expect(
        declaredAsset.values,
        contains(path),
        reason: '$path is in the bundle and nothing declares it',
      );
    }
  });

  test('the golden harness loads every one of them', () {
    for (final String family in declared) {
      expect(
        merzoxGoldenFontAssets.keys,
        contains(family),
        reason: '$family is declared but no capture would draw it',
      );
      expect(
        merzoxGoldenFontAssets[family],
        <String>[declaredAsset[family]!],
        reason: '$family is loaded from a different file than it ships from',
      );
    }
  });

  test('a family is named for its folder and its file', () {
    for (final MapEntry<String, String> entry in declaredAsset.entries) {
      final List<String> parts = entry.value.split('/');
      final String folder = parts[parts.length - 2];
      final String basename = parts.last.replaceAll('.ttf', '');

      expect(
        basename,
        entry.key,
        reason: 'the file under ${entry.key} should be named for it',
      );

      final String expectedPrefix = folder
          .split('_')
          .map((String w) => w[0].toUpperCase() + w.substring(1))
          .join();
      expect(
        entry.key.startsWith(expectedPrefix),
        isTrue,
        reason:
            '${entry.key} sits in $folder/ and should begin with '
            '$expectedPrefix, so the family says which screen it is for',
      );
    }
  });

  test('no two families share a file', () {
    // Sharing one would be the old arrangement creeping back: two screens
    // that move together whether or not anybody meant them to.
    final List<String> assets = declaredAsset.values.toList();
    expect(
      assets.length,
      assets.toSet().length,
      reason: 'two families are declared from the same file',
    );
  });
}
