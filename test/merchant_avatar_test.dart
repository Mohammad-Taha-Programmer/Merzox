import 'dart:async';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/business/shell/widgets/merchant_avatar_button.dart';

import 'localization_test_harness.dart';
import 'network_image_harness.dart';

/// The account's picture in the merchant's top bar.
///
/// The bar drew one fixed storefront glyph, so every merchant's screen looked
/// like every other merchant's, and the account document had nowhere to keep a
/// picture even if one existed. The picture is its own control now - the board
/// offers no other way in - so the same widget has to show it, replace it, and
/// hold its nerve when it will not load.

final Uint8List _bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

Future<List<Uint8List>> _pumpAvatar(
  WidgetTester tester, {
  String avatarUrl = '',
  Uint8List? picked,
  Future<void> Function(Uint8List bytes)? onPicked,
}) async {
  final List<Uint8List> uploaded = <Uint8List>[];

  await pumpLocalized(
    tester,
    Scaffold(
      body: Center(
        child: MerchantAvatarButton(
          avatarUrl: avatarUrl,
          picker: (AvatarSource _) async => picked,
          onPicked:
              onPicked ??
              (Uint8List bytes) async {
                uploaded.add(bytes);
              },
        ),
      ),
    ),
  );

  return uploaded;
}

/// Holds the picture and picks a source.
///
/// A hold, not a tap: a tap opens the picture large. Replacing it cannot be
/// undone once the old file is deleted, so it takes a deliberate press.
Future<void> _holdAndChoose(WidgetTester tester, String source) async {
  await tester.longPress(
    find.byKey(const ValueKey<String>('merchantAvatar.button')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey<String>('merchantAvatar.$source')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  group('the picture in the bar', () {
    testWidgets('an account with no picture keeps the placeholder', (
      WidgetTester tester,
    ) async {
      await _pumpAvatar(tester);

      expect(
        find.byKey(const ValueKey<String>('merchantAvatar.image')),
        findsNothing,
      );
      expect(find.byIcon(Icons.storefront_rounded), findsOneWidget);
    });

    testWidgets('an account with one shows it, cropped to a circle', (
      WidgetTester tester,
    ) async {
      serveNetworkImage();
      await _pumpAvatar(tester, avatarUrl: 'https://i.ibb.co/x/pic.png');
      await settleFrames(tester);

      final Finder image = find.byKey(
        const ValueKey<String>('merchantAvatar.image'),
      );
      final bool drawn = image.evaluate().isNotEmpty;
      final BoxFit? fit = drawn ? tester.widget<Image>(image).fit : null;
      final bool clipped = find.byType(ClipOval).evaluate().isNotEmpty;
      final bool fellBack = find
          .byIcon(Icons.storefront_rounded)
          .evaluate()
          .isNotEmpty;
      stopServingNetworkImages();

      expect(drawn, isTrue);
      expect(fit, BoxFit.cover, reason: 'a portrait must fill the circle');
      expect(clipped, isTrue);
      expect(fellBack, isFalse, reason: 'a good picture must not fall back');
    });

    testWidgets('a picture that will not load falls back, never a broken box', (
      WidgetTester tester,
    ) async {
      serveNetworkImage(merzoxNotAnImage);
      await _pumpAvatar(tester, avatarUrl: 'https://i.ibb.co/gone/pic.png');
      await settleFrames(tester);

      final bool fellBack = find
          .byIcon(Icons.storefront_rounded)
          .evaluate()
          .isNotEmpty;
      stopServingNetworkImages();

      // The placeholder, not the grey box a failed `Image.network` draws.
      expect(fellBack, isTrue);
    });
  });

  group('looking at it', () {
    testWidgets('a tap opens it at a size a portrait can be judged at', (
      WidgetTester tester,
    ) async {
      serveNetworkImage();
      await _pumpAvatar(tester, avatarUrl: 'https://i.ibb.co/x/pic.png');
      await settleFrames(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('merchantAvatar.button')),
      );
      await settleFrames(tester);

      final bool opened = find
          .byKey(const ValueKey<String>('merchantAvatar.enlarged'))
          .evaluate()
          .isNotEmpty;
      stopServingNetworkImages();

      expect(opened, isTrue);
    });

    testWidgets('it closes again on a touch', (WidgetTester tester) async {
      serveNetworkImage();
      await _pumpAvatar(tester, avatarUrl: 'https://i.ibb.co/x/pic.png');
      await settleFrames(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('merchantAvatar.button')),
      );
      await settleFrames(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('merchantAvatar.enlarged')),
      );
      await settleFrames(tester);

      final bool stillOpen = find
          .byKey(const ValueKey<String>('merchantAvatar.enlarged'))
          .evaluate()
          .isNotEmpty;
      stopServingNetworkImages();

      expect(stillOpen, isFalse);
    });

    testWidgets('an account with no picture opens nothing', (
      WidgetTester tester,
    ) async {
      await _pumpAvatar(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('merchantAvatar.button')),
      );
      await settleFrames(tester);

      // An empty box would be a worse answer than doing nothing.
      expect(
        find.byKey(const ValueKey<String>('merchantAvatar.enlarged')),
        findsNothing,
      );
    });
  });

  group('replacing it', () {
    testWidgets('a hold offers the camera and the gallery', (
      WidgetTester tester,
    ) async {
      await _pumpAvatar(tester);

      await tester.longPress(
        find.byKey(const ValueKey<String>('merchantAvatar.button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('profileEdit.avatarFromCamera'.tr()), findsOneWidget);
      expect(find.text('profileEdit.avatarFromGallery'.tr()), findsOneWidget);
    });

    testWidgets('a plain tap does not offer to replace it', (
      WidgetTester tester,
    ) async {
      serveNetworkImage();
      await _pumpAvatar(tester, avatarUrl: 'https://i.ibb.co/x/pic.png');
      await settleFrames(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('merchantAvatar.button')),
      );
      await settleFrames(tester);

      final bool offered = find
          .text('profileEdit.avatarFromGallery'.tr())
          .evaluate()
          .isNotEmpty;
      stopServingNetworkImages();

      // The control sits beside the notification bell. A stray touch must not
      // start replacing a picture that cannot be recovered afterwards.
      expect(offered, isFalse);
    });

    testWidgets('the hint tells the merchant which gesture replaces it', (
      WidgetTester tester,
    ) async {
      await _pumpAvatar(tester);

      final Tooltip hint = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(hint.message, 'profileEdit.holdToChangeAvatar'.tr());
    });

    testWidgets('the chosen bytes are handed over, from either source', (
      WidgetTester tester,
    ) async {
      for (final String source in <String>['camera', 'gallery']) {
        final List<Uint8List> uploaded = await _pumpAvatar(
          tester,
          picked: _bytes,
        );
        await _holdAndChoose(tester, source);

        expect(uploaded, <Uint8List>[_bytes], reason: source);
      }
    });

    testWidgets('backing out of the picker uploads nothing', (
      WidgetTester tester,
    ) async {
      // The merchant opened the gallery and changed their mind. That is not a
      // failure and must not send an empty picture.
      final List<Uint8List> uploaded = await _pumpAvatar(tester, picked: null);
      await _holdAndChoose(tester, 'gallery');

      expect(uploaded, isEmpty);
    });

    testWidgets('dismissing the sheet uploads nothing either', (
      WidgetTester tester,
    ) async {
      final List<Uint8List> uploaded = await _pumpAvatar(
        tester,
        picked: _bytes,
      );

      await tester.longPress(
        find.byKey(const ValueKey<String>('merchantAvatar.button')),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(uploaded, isEmpty);
    });

    testWidgets('a second tap during an upload is ignored', (
      WidgetTester tester,
    ) async {
      int uploads = 0;
      final Completer<void> hanging = Completer<void>();

      await _pumpAvatar(
        tester,
        picked: _bytes,
        onPicked: (Uint8List _) {
          uploads += 1;
          return hanging.future;
        },
      );

      await tester.longPress(
        find.byKey(const ValueKey<String>('merchantAvatar.button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('merchantAvatar.gallery')),
      );
      await settleFrames(tester);
      expect(uploads, 1);

      // Still uploading. Tapping again would send the same picture twice and
      // race over which one lands.
      // A spinner is turning, so the tree never goes idle: `pumpAndSettle`
      // would wait for ever. A bounded pump is the only honest wait here.
      await tester.tap(
        find.byKey(const ValueKey<String>('merchantAvatar.button')),
      );
      await settleFrames(tester);
      expect(find.text('profileEdit.avatarFromGallery'.tr()), findsNothing);
      expect(uploads, 1);

      hanging.complete();
      await settleFrames(tester);
    });
  });
}
