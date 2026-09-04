import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Which face the follow control wears in each state.
///
/// The control is the one place on a business card that says whether the
/// customer already follows the shop, and the pair had drifted: both faces
/// were fond ones, so a followed card and an unfollowed card looked equally
/// pleased and the state was unreadable at a glance.
///
/// This reads the source rather than the rendered pixels on purpose. The
/// control is private to the home screen, and the golden harness carries no
/// emoji font, so a capture shows a placeholder box whichever face is chosen -
/// it cannot tell the two apart, and neither could a reviewer reading it.
void main() {
  const String followed = '\u{1F60D}'; // 😍 smiling face with heart-eyes
  const String notFollowed = '\u{1F612}'; // 😒 unamused face

  late String source;

  setUpAll(() async {
    source = await File('lib/features/home/home_screen.dart').readAsString();
  });

  test('the followed card wears the warm face', () {
    expect(
      source.contains("followed ? '$followed' : '$notFollowed'"),
      isTrue,
      reason:
          'the follow control must read followed -> $followed, '
          'not followed -> $notFollowed',
    );
  });

  test('the two states do not share a face', () {
    expect(followed, isNot(notFollowed));

    // The old pair: two affectionate faces, one of which meant "not yet".
    expect(source.contains('\u{1F970}'), isFalse);
  });
}
