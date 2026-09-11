import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Which face the follow control wears in each state, and whether the app can
/// actually load it.
///
/// The control is the one place on a business card that says whether the
/// customer already follows the shop, and the pair had drifted: both faces
/// were fond ones, so a followed card and an unfollowed card looked equally
/// pleased and the state was unreadable at a glance.
///
/// The faces used to be emoji characters. That is why this reads the source
/// rather than a capture: the golden harness carries no emoji font, so every
/// board drew a placeholder box whichever face was chosen and no picture could
/// tell the two apart. They are the project's own pictures now and the boards
/// do show them - but a board only proves the state it was captured in, and
/// what this file is for is the pairing.
///
/// The three checks below the pairing are the ones the emoji version could not
/// make. A picture has to exist and has to be declared, and a folder left out
/// of `pubspec.yaml` is the worst kind of missing: it resolves in the editor,
/// survives `flutter analyze`, and throws the first time a customer scrolls
/// past a shop.
void main() {
  const String followedFace = 'happy.png';
  const String notFollowedFace = 'sad.png';
  const String folder = 'assets/images/follow_business_emoji_pics/';

  late String source;
  late String squashed;
  late String pubspec;

  setUpAll(() async {
    source = await File('lib/features/home/home_screen.dart').readAsString();
    pubspec = await File('pubspec.yaml').readAsString();

    // Whitespace removed, and the string concatenation the formatter may split
    // a long path across closed up. Matching the exact lines instead made this
    // fail on a line ending rather than on anything about the faces.
    squashed = source.replaceAll(RegExp(r'\s+'), '').replaceAll("''", '');
  });

  test('the followed card wears the warm face', () {
    expect(
      squashed.contains('followed?_followedFace:_unfollowedFace'),
      isTrue,
      reason: 'the follow control must choose its face from `followed`',
    );
    expect(
      squashed.contains(
        "const String_followedFace='$folder$followedFace';".replaceAll(' ', ''),
      ),
      isTrue,
      reason: 'followed has to be the warm face, $followedFace',
    );
    expect(
      squashed.contains(
        "const String_unfollowedFace='$folder$notFollowedFace';".replaceAll(
          ' ',
          '',
        ),
      ),
      isTrue,
      reason: 'not followed has to be the flat face, $notFollowedFace',
    );
  });

  test('the two states do not share a face', () {
    expect(followedFace, isNot(notFollowedFace));

    // The old pair: two affectionate faces, one of which meant "not yet".
    expect(source.contains('\u{1F970}'), isFalse);

    // And the emoji characters themselves, which a device font could always
    // decline to draw.
    expect(source.contains('\u{1F60D}'), isFalse);
    expect(source.contains('\u{1F612}'), isFalse);
  });

  test('both faces are on disk', () {
    for (final String face in <String>[followedFace, notFollowedFace]) {
      expect(
        File('$folder$face').existsSync(),
        isTrue,
        reason: '$folder$face is drawn by the home screen and is not there',
      );
    }
  });

  test('their folder is declared, so the picture loads on a phone too', () {
    // `assets/images/` is not recursive. A subfolder that is not named here
    // resolves in the editor and throws at runtime, which is a crash nothing
    // in this repository would have caught before it shipped.
    expect(
      pubspec.contains('- $folder'),
      isTrue,
      reason: 'pubspec.yaml must list $folder among its assets',
    );
  });
}
