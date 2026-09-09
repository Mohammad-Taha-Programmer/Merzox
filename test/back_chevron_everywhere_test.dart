import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every board's way back is the artboard's chevron.
///
/// Held as a reading of the source rather than by pumping fourteen screens:
/// each of these headers needs its own blocs, sessions and fixtures to build,
/// and what is being asked is not how any one of them behaves - it is that the
/// same mark is used across all of them. A test that pumped them would be
/// mostly fixture, and would go stale a screen at a time.
///
/// The screens whose way back is checked by pumping - `الرسائل`, `طلباتي`,
/// `المفضلة`, `من نحن` - are checked there for the press as well as the mark.

final Directory _lib = Directory('lib');

List<File> _dartFiles() => _lib
    .listSync(recursive: true)
    .whereType<File>()
    .where((File file) => file.path.endsWith('.dart'))
    .toList();

/// The one board that still draws Material's arrow, and is meant to.
///
/// `الإشعارات` lays its header out as a `Row` rather than a `Stack`, so the
/// swap is a change to that row's spacing and not the substitution the others
/// took. It was not part of the list, and is named here so its absence is a
/// decision on the record rather than something overlooked.
const String _knownException = 'notifications_page.dart';

void main() {
  test('no board reaches for Material\'s shafted arrow', () {
    final List<String> offenders = <String>[];

    for (final File file in _dartFiles()) {
      if (file.path.endsWith(_knownException)) continue;

      final String source = file.readAsStringSync();
      // The widget in use, not the word: the shared chevron's own doc comment
      // names `BackButton` to say what it replaced.
      if (RegExp(r'\bBackButton\s*\(').hasMatch(source)) {
        offenders.add(file.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'these draw a shafted arrow where the artboards draw a chevron',
    );
  });

  test('the one exception is still there to be found', () {
    // If `الإشعارات` is converted, this fails and the exemption above goes
    // with it - an allowance nobody can retire is how a list of exceptions
    // grows into the rule.
    final Iterable<File> matches = _dartFiles().where(
      (File file) => file.path.endsWith(_knownException),
    );

    expect(matches, hasLength(1), reason: '$_knownException moved or went');
    expect(
      RegExp(r'\bBackButton\s*\(').hasMatch(matches.single.readAsStringSync()),
      isTrue,
      reason:
          '$_knownException no longer draws the arrow, so it needs no '
          'exemption - delete it from this test',
    );
  });

  test('every swapped board names its own way back', () {
    // The keys are what a test reaches for, and two boards sharing one would
    // find the wrong screen's button without saying so.
    final Set<String> seen = <String>{};
    final RegExp key = RegExp(r"ValueKey<String>\(\s*'([\w.]+\.back)'");

    for (final File file in _dartFiles()) {
      for (final RegExpMatch match in key.allMatches(
        file.readAsStringSync(),
      )) {
        expect(
          seen.add(match.group(1)!),
          isTrue,
          reason: '${match.group(1)} is used by more than one board',
        );
      }
    }

    // The seven this pass converted, plus the four that came before it.
    expect(seen.length, greaterThanOrEqualTo(11));
  });
}
