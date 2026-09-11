import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/widgets/merzox_picture_field.dart';
import 'package:merzox/core/widgets/merzox_profile.dart';

import 'localization_test_harness.dart';

/// Setting the account's own picture.
///
/// The column for it existed on the account and the endpoint existed on the
/// server - the shop-settings screen has been using it all along - and only
/// the customer's way in was missing. So what is checked here is that way in:
/// the three sources, what each one does with what it is given, and that a
/// picture nobody chose changes nothing.

class _Recorder {
  final List<Uint8List> uploaded = <Uint8List>[];
  final List<MerzoxPictureSource> asked = <MerzoxPictureSource>[];
  final List<String> links = <String>[];

  Uint8List? deviceAnswer = Uint8List.fromList(<int>[1, 2, 3]);
  Uint8List? linkAnswer = Uint8List.fromList(<int>[4, 5, 6]);
  String? storedAt = 'https://images.test/avatar.png';

  Future<Uint8List?> device(MerzoxPictureSource source) async {
    asked.add(source);
    return deviceAnswer;
  }

  Future<Uint8List?> link(String url) async {
    links.add(url);
    return linkAnswer;
  }

  Future<String?> onPicked(Uint8List bytes) async {
    uploaded.add(bytes);
    return storedAt;
  }
}

Future<void> _pumpAvatar(
  WidgetTester tester,
  _Recorder recorder, {
  String url = '',
}) {
  return pumpLocalized(
    tester,
    Scaffold(
      body: Center(
        child: MerzoxProfileAvatar(
          child: MerzoxPictureField(
            url: url,
            onPicked: recorder.onPicked,
            devicePicker: recorder.device,
            linkReader: recorder.link,
            shape: BoxShape.circle,
            size: kProfileAvatarDiameter,
            hintKey: 'profile.pictureChangeHint',
            keyPrefix: 'profileAvatar',
            placeholder: const Icon(Icons.person_outline_rounded),
          ),
        ),
      ),
    ),
  );
}

Finder _avatar() => find.byKey(const ValueKey<String>('profileAvatar.box'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  group('the three ways in', () {
    testWidgets('a photograph is taken and sent', (tester) async {
      final _Recorder recorder = _Recorder();
      await _pumpAvatar(tester, recorder);

      await tester.longPress(_avatar());
      await settleFrames(tester);
      await tester.tap(find.byKey(const ValueKey<String>('storeLogo.camera')));
      await settleFrames(tester);

      expect(recorder.asked, <MerzoxPictureSource>[MerzoxPictureSource.camera]);
      expect(recorder.uploaded.single, <int>[1, 2, 3]);
    });

    testWidgets('or chosen from the gallery', (tester) async {
      final _Recorder recorder = _Recorder();
      await _pumpAvatar(tester, recorder);

      await tester.longPress(_avatar());
      await settleFrames(tester);
      await tester.tap(find.byKey(const ValueKey<String>('storeLogo.gallery')));
      await settleFrames(tester);

      expect(recorder.asked, <MerzoxPictureSource>[
        MerzoxPictureSource.gallery,
      ]);
      expect(recorder.uploaded, hasLength(1));
    });

    testWidgets('or fetched from a link, and sent as bytes like the rest', (
      tester,
    ) async {
      // The app downloads the link rather than storing it. All three ways then
      // end at one upload and one stored file, which is what lets a picture be
      // replaced and deleted like any other - a link kept as a link could be
      // neither, and would go dark the day its host did.
      final _Recorder recorder = _Recorder();
      await _pumpAvatar(tester, recorder);

      await tester.longPress(_avatar());
      await settleFrames(tester);
      await tester.tap(find.byKey(const ValueKey<String>('storeLogo.link')));
      await settleFrames(tester);

      await tester.enterText(
        find.byKey(const ValueKey<String>('storeLogo.linkField')),
        'https://images.test/portrait.png',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('storeLogo.linkConfirm')),
      );
      await settleFrames(tester);

      expect(recorder.links.single, 'https://images.test/portrait.png');
      expect(recorder.uploaded.single, <int>[4, 5, 6]);
      // Nothing was asked of the camera or the gallery.
      expect(recorder.asked, isEmpty);
    });
  });

  group('what does not upload', () {
    testWidgets('backing out of the picker sends nothing', (tester) async {
      final _Recorder recorder = _Recorder()..deviceAnswer = null;
      await _pumpAvatar(tester, recorder);

      await tester.longPress(_avatar());
      await settleFrames(tester);
      await tester.tap(find.byKey(const ValueKey<String>('storeLogo.camera')));
      await settleFrames(tester);

      // Changing your mind is not a failure and is not reported as one.
      expect(recorder.uploaded, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a link that is not a link is refused before any upload', (
      tester,
    ) async {
      final _Recorder recorder = _Recorder();
      await _pumpAvatar(tester, recorder);

      await tester.longPress(_avatar());
      await settleFrames(tester);
      await tester.tap(find.byKey(const ValueKey<String>('storeLogo.link')));
      await settleFrames(tester);

      await tester.enterText(
        find.byKey(const ValueKey<String>('storeLogo.linkField')),
        'javascript:alert(1)',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('storeLogo.linkConfirm')),
      );
      await settleFrames(tester);

      expect(recorder.links, isEmpty);
      expect(recorder.uploaded, isEmpty);
    });

    testWidgets('an upload that stored nothing says so', (tester) async {
      final _Recorder recorder = _Recorder()..storedAt = null;
      await _pumpAvatar(tester, recorder);

      await tester.longPress(_avatar());
      await settleFrames(tester);
      await tester.tap(find.byKey(const ValueKey<String>('storeLogo.camera')));
      await settleFrames(tester);

      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('what a tap does', () {
    testWidgets('with no picture yet, it opens the picker', (tester) async {
      // There is nothing to enlarge, and an empty frame that did nothing when
      // tapped would be a dead end.
      final _Recorder recorder = _Recorder();
      await _pumpAvatar(tester, recorder);

      await tester.tap(_avatar());
      await settleFrames(tester);

      expect(
        find.byKey(const ValueKey<String>('storeLogo.camera')),
        findsOneWidget,
      );
    });

    testWidgets('the placeholder stands in until there is one', (tester) async {
      await _pumpAvatar(tester, _Recorder());

      expect(
        find.byKey(const ValueKey<String>('profileAvatar.placeholder')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('profileAvatar.image')),
        findsNothing,
      );
    });
  });
}
