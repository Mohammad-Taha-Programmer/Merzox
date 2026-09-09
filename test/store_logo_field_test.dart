import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/widgets/merzox_picture_field.dart';

import 'localization_test_harness.dart';
import 'network_image_harness.dart';

/// The shop's logo, and the three ways to change it.
///
/// A tap looks at it, a press replaces it, and an empty box does the second
/// thing because there is nothing to look at. All three sources end at the
/// same bytes and the same upload, which is what keeps one picture from
/// becoming two.

final Uint8List _bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

const String _logo = 'https://images.test/logo.png';

class _Recorder {
  final List<Uint8List> uploaded = <Uint8List>[];
  final List<MerzoxPictureSource> asked = <MerzoxPictureSource>[];
  final List<String> links = <String>[];

  String? answer = 'https://images.test/new.png';

  Future<String?> onPicked(Uint8List bytes) async {
    uploaded.add(bytes);
    return answer;
  }

  Future<Uint8List?> device(MerzoxPictureSource source) async {
    asked.add(source);
    return _bytes;
  }

  Future<Uint8List?> link(String url) async {
    links.add(url);
    return _bytes;
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Recorder recorder, {
  String url = '',
}) async {
  await pumpLocalized(
    tester,
    Scaffold(
      body: Center(
        child: MerzoxPictureField(
          url: url,
          onPicked: recorder.onPicked,
          devicePicker: recorder.device,
          linkReader: recorder.link,
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  group('the box', () {
    testWidgets('a shop with no logo shows the board\'s empty box', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _Recorder());

      expect(
        find.byKey(const ValueKey<String>('storeLogo.placeholder')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('storeLogo.image')),
        findsNothing,
      );
    });

    testWidgets('and a tap on it asks where the logo should come from', (
      WidgetTester tester,
    ) async {
      // There is nothing to enlarge, and a box that did nothing when tapped
      // would be a dead end on the one screen that sets the logo.
      await _pump(tester, _Recorder());

      await tester.tap(find.byKey(const ValueKey<String>('storeLogo.box')));
      await settleFrames(tester);

      expect(
        find.byKey(const ValueKey<String>('storeLogo.camera')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('storeLogo.gallery')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('storeLogo.link')),
        findsOneWidget,
      );
    });

    testWidgets('a tap on a logo opens it large, and does not replace it', (
      WidgetTester tester,
    ) async {
      serveNetworkImage();
      final _Recorder recorder = _Recorder();
      await _pump(tester, recorder, url: _logo);
      await settleFrames(tester);

      await tester.tap(find.byKey(const ValueKey<String>('storeLogo.box')));
      await settleFrames(tester);

      final bool opened = find
          .byKey(const ValueKey<String>('storeLogo.enlarged'))
          .evaluate()
          .isNotEmpty;
      stopServingNetworkImages();

      expect(opened, isTrue);
      // Looking is the common thing; replacing cannot be undone once the old
      // file is deleted, so a stray touch must not start it.
      expect(recorder.asked, isEmpty);
      expect(recorder.uploaded, isEmpty);
    });

    testWidgets('a press on a logo asks where the new one comes from', (
      WidgetTester tester,
    ) async {
      serveNetworkImage();
      await _pump(tester, _Recorder(), url: _logo);
      await settleFrames(tester);

      await tester.longPress(
        find.byKey(const ValueKey<String>('storeLogo.box')),
      );
      await settleFrames(tester);

      final bool asked = find
          .byKey(const ValueKey<String>('storeLogo.camera'))
          .evaluate()
          .isNotEmpty;
      stopServingNetworkImages();

      expect(asked, isTrue);
    });

    testWidgets('a logo that will not load falls back to the empty box', (
      WidgetTester tester,
    ) async {
      // A broken-image box would be a worse answer than the placeholder, and
      // the merchant still needs the way in to replace it.
      serveNetworkImage(merzoxNotAnImage);
      await _pump(tester, _Recorder(), url: _logo);
      await settleFrames(tester);

      final bool empty = find
          .byKey(const ValueKey<String>('storeLogo.placeholder'))
          .evaluate()
          .isNotEmpty;
      stopServingNetworkImages();

      expect(empty, isTrue);
    });
  });

  group('the three ways in', () {
    for (final (String key, MerzoxPictureSource source) in <(
      String,
      MerzoxPictureSource,
    )>[
      ('storeLogo.camera', MerzoxPictureSource.camera),
      ('storeLogo.gallery', MerzoxPictureSource.gallery),
    ]) {
      testWidgets('$key reads the device and uploads what it read', (
        WidgetTester tester,
      ) async {
        final _Recorder recorder = _Recorder();
        await _pump(tester, recorder);

        await tester.tap(find.byKey(const ValueKey<String>('storeLogo.box')));
        await settleFrames(tester);
        await tester.tap(find.byKey(ValueKey<String>(key)));
        await settleFrames(tester);

        expect(recorder.asked, <MerzoxPictureSource>[source]);
        expect(recorder.uploaded, <Uint8List>[_bytes]);
      });
    }

    testWidgets('a link is fetched, and its bytes take the same road', (
      WidgetTester tester,
    ) async {
      // The bytes are what is uploaded, not the address. A logo kept as
      // somebody else's link could not be resized, could not be deleted, and
      // would go dark the day its host did.
      final _Recorder recorder = _Recorder();
      await _pump(tester, recorder);

      await tester.tap(find.byKey(const ValueKey<String>('storeLogo.box')));
      await settleFrames(tester);
      await tester.tap(find.byKey(const ValueKey<String>('storeLogo.link')));
      await settleFrames(tester);

      await tester.enterText(
        find.byKey(const ValueKey<String>('storeLogo.linkField')),
        'https://elsewhere.test/mark.png',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('storeLogo.linkConfirm')),
      );
      await settleFrames(tester);

      expect(recorder.links, <String>['https://elsewhere.test/mark.png']);
      expect(recorder.uploaded, <Uint8List>[_bytes]);
    });

    testWidgets('a link that is not one is refused before anything is read', (
      WidgetTester tester,
    ) async {
      final _Recorder recorder = _Recorder();
      await _pump(tester, recorder);

      await tester.tap(find.byKey(const ValueKey<String>('storeLogo.box')));
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
      // The dialog stays open with its complaint rather than closing on a
      // value it will not use.
      expect(
        find.byKey(const ValueKey<String>('storeLogo.linkField')),
        findsOneWidget,
      );
    });

    testWidgets('an upload that stores nothing says so', (
      WidgetTester tester,
    ) async {
      final _Recorder recorder = _Recorder()..answer = '';
      await _pump(tester, recorder);

      await tester.tap(find.byKey(const ValueKey<String>('storeLogo.box')));
      await settleFrames(tester);
      await tester.tap(find.byKey(const ValueKey<String>('storeLogo.gallery')));
      await settleFrames(tester);

      expect(find.text('تعذر رفع الصورة، حاول مرة أخرى'), findsOneWidget);
    });
  });

  group('fetching a pasted link', () {
    Dio dioAnswering({
      required String contentType,
      required List<int> body,
      int status = 200,
    }) {
      final Dio dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest:
              (RequestOptions options, RequestInterceptorHandler handler) {
                handler.resolve(
                  Response<List<int>>(
                    requestOptions: options,
                    statusCode: status,
                    data: body,
                    headers: Headers.fromMap(<String, List<String>>{
                      Headers.contentTypeHeader: <String>[contentType],
                    }),
                  ),
                );
              },
        ),
      );
      return dio;
    }

    test('a scheme that is not http is never fetched', () async {
      expect(await fetchPictureBytes('javascript:alert(1)'), isNull);
      expect(await fetchPictureBytes('ftp://host/x.png'), isNull);
      expect(await fetchPictureBytes('/relative/x.png'), isNull);
      expect(await fetchPictureBytes(''), isNull);
    });

    test('a page that is not a picture is not a logo', () async {
      // Plenty of hosts answer 200 with an HTML error page. Uploading that
      // would put a broken image on the shop.
      final Uint8List? bytes = await fetchPictureBytes(
        'https://host.test/x.png',
        dio: dioAnswering(
          contentType: 'text/html',
          body: <int>[60, 104, 116],
        ),
      );

      expect(bytes, isNull);
    });

    test('more than the server would take is not carried at all', () async {
      final Uint8List? bytes = await fetchPictureBytes(
        'https://host.test/x.png',
        dio: dioAnswering(
          contentType: 'image/png',
          body: List<int>.filled(kMerzoxPictureMaxBytes + 1, 7),
        ),
      );

      expect(bytes, isNull);
    });

    test('a picture comes back as its bytes', () async {
      final Uint8List? bytes = await fetchPictureBytes(
        'https://host.test/x.png',
        dio: dioAnswering(
          contentType: 'image/png; charset=binary',
          body: <int>[1, 2, 3],
        ),
      );

      expect(bytes, isNotNull);
      expect(bytes, <int>[1, 2, 3]);
    });
  });
}
