import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// No box may have its controllers taken out from under it.
///
/// `showDialog` and `showModalBottomSheet` return the moment the route is
/// popped, not when the box is gone. It is still on screen fading out, its
/// fields still mounted and still holding whatever controllers were handed to
/// them. Disposing those on the line after the `await` throws - and the throw
/// leaves the subtree half-updated, so what the reader actually sees is
/// `'_dependents.isEmpty': is not true`, a red screen naming nothing that
/// happened.
///
/// This has now been written three times in this repository: once on the
/// orders screen, once when saving a courier, and once when removing a product
/// option. The first two reached a phone. It is an easy thing to write and an
/// expensive thing to find, because the error arrives several steps downstream
/// of the line that caused it.
///
/// So it is checked rather than remembered. The rule is not "never dispose" -
/// it is that the box owns what the box uses: a `StatefulWidget` built by the
/// builder, disposing in its own `dispose`, which runs when the route is truly
/// gone. `askForOrderText` and `askForCourier` are both that shape.
///
/// Read as text on purpose. What is wrong here is a shape in the source, and
/// no amount of running the app finds it except by crashing.
void main() {
  test('nothing disposes a controller the moment a box closes', () {
    final RegExp opener = RegExp(r'await show(Dialog|ModalBottomSheet)');

    final List<String> offences = <String>[];

    for (final FileSystemEntity entity in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final String source = entity.readAsStringSync();

      for (final RegExpMatch match in opener.allMatches(source)) {
        // What runs after the box closes, up to the next one being opened.
        final String after = source.substring(
          match.end,
          (match.end + 1400).clamp(0, source.length),
        );

        final int nextOpener = after.indexOf('await show');
        final String window = nextOpener < 0
            ? after
            : after.substring(0, nextOpener);

        if (!window.contains('.dispose()')) continue;

        final int line =
            '\n'.allMatches(source.substring(0, match.start)).length + 1;

        offences.add('${entity.path.replaceAll(r'\', '/')}:$line');
      }
    }

    expect(
      offences,
      isEmpty,
      reason:
          'a box closing is not a box gone. Give the controllers to a widget '
          'the builder makes, and let its own dispose take them: see '
          'askForCourier. Found at:\n  ${offences.join('\n  ')}',
    );
  });
}
