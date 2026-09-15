import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A field that asks for a number gets a number pad, and one that asks for an
/// address gets the pad with `@` on it.
///
/// A field that names no `keyboardType` gets the letters. That is right for a
/// name and wrong for a price, and the wrongness cannot be seen in a capture -
/// it shows up only when somebody types, as one extra press to reach the
/// digits, every single time.
///
/// Read out of the source rather than by pumping thirty screens: what is being
/// asked is not how any one screen behaves but that none of them forgot, and a
/// test that pumped them would be mostly fixture and would go stale a screen at
/// a time.
///
/// It reads the field's own parentheses, so what it is matching is the field's
/// controller, label and hint - `merchantProduct.priceHint`, `_phone`,
/// `emailLabel`. A field about one of these things and silent about its
/// keyboard is the fault; a paragraph field that happens to mention a price in
/// its hint text would be a false positive, and there are none today.
final RegExp _fieldCall = RegExp(
  r'\b(TextFormField|TextField|ProductField|MerzoxTextField|_field|_XdField)'
  r'\s*\(',
);

/// The things a letters keyboard is wrong for.
final RegExp _wantsItsOwnPad = RegExp(
  r'phone|price|quantity|stock|email|amount',
  caseSensitive: false,
);

final RegExp _saysKeyboard = RegExp(r'keyboardType\s*:');

/// Line comments, which are prose and not part of what the field asks for.
///
/// Without this the guard read "a phone held at arm's length" out of a note
/// about type size and reported the search box beside it.
final RegExp _comment = RegExp(r'//.*');

String _codeOnly(String body) => body.replaceAll(_comment, '');

/// Each field call in [source], as the text between its own parentheses.
Iterable<({int line, String body})> _fieldBodies(String source) sync* {
  for (final RegExpMatch match in _fieldCall.allMatches(source)) {
    final int open = match.end - 1;
    int depth = 0;

    for (int i = open; i < source.length; i += 1) {
      if (source[i] == '(') {
        depth += 1;
      } else if (source[i] == ')') {
        depth -= 1;
        if (depth == 0) {
          yield (
            line: '\n'.allMatches(source.substring(0, match.start)).length + 1,
            body: source.substring(open + 1, i),
          );
          break;
        }
      }
    }
  }
}

void main() {
  test('every field about a number or an address names its keyboard', () {
    final List<String> offenders = <String>[];

    for (final FileSystemEntity entity in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final String source = entity.readAsStringSync();

      for (final ({int line, String body}) field in _fieldBodies(source)) {
        final String code = _codeOnly(field.body);
        if (!_wantsItsOwnPad.hasMatch(code)) continue;
        if (_saysKeyboard.hasMatch(code)) continue;

        offenders.add('${entity.path.replaceAll(r'\', '/')}:${field.line}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'these ask for a number or an address and would be given the '
          'letters: ${offenders.join(', ')}',
    );
  });

  // The scan is worth nothing if it is matching nothing, so it is made to
  // prove it can see a field and can tell the two cases apart.
  test('the scan finds fields, and tells a named keyboard from none', () {
    const String sample = '''
      TextFormField(controller: _phone, keyboardType: kMerzoxPhoneKeyboard)
      TextFormField(controller: _name)
      TextFormField(controller: _price)
      TextField(controller: _search) // read on a phone at arm's length
    ''';

    final List<({int line, String body})> found = _fieldBodies(sample).toList();

    expect(found.length, 4);
    expect(
      found.where((f) => _wantsItsOwnPad.hasMatch(_codeOnly(f.body))).length,
      2,
      reason:
          'the phone and the price are the two it should care about - the '
          'search box only mentions a phone in a comment',
    );
    expect(
      found
          .where(
            (f) =>
                _wantsItsOwnPad.hasMatch(_codeOnly(f.body)) &&
                !_saysKeyboard.hasMatch(_codeOnly(f.body)),
          )
          .length,
      1,
      reason: 'only the price is silent about its keyboard',
    );
  });
}
