import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/widgets/remote_circle_avatar.dart';

import 'localization_test_harness.dart';

/// A round picture that survives not arriving.
///
/// `CircleAvatar.backgroundImage` paints through a `DecorationImage`, and a
/// decoration has nowhere to put an error builder - so a logo whose host does
/// not resolve threw on every single paint. The console filled with the same
/// `Failed host lookup` over and over, and the circle stayed blank with no
/// explanation. A conversation left behind by a deleted shop was enough.

/// A one-pixel PNG, so a request has something real to decode.
final Uint8List _png = Uint8List.fromList(<int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

/// Bytes that are not an image: what a dead or replaced host looks like from
/// here - the request answers and the decode does not.
final Uint8List _notAnImage = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);

/// Serves [payload] to any image request.
///
/// The framework's own seam, not `HttpOverrides`: Flutter keeps one shared
/// client for network images and builds it once, so the second test in a file
/// would otherwise be served by the first test's override.
void _serve(Uint8List payload) {
  debugNetworkImageHttpClientProvider = () => _Client(payload);
}

/// Put back inside the test body: `testWidgets` asserts no painting debug
/// variable outlived the test, and checks that before any teardown runs.
void _stopServing() {
  debugNetworkImageHttpClientProvider = null;
  PaintingBinding.instance.imageCache.clear();
  PaintingBinding.instance.imageCache.clearLiveImages();
}

const Key _fallback = ValueKey<String>('fallback');
const Key _picture = ValueKey<String>('merzox.remoteAvatar.image');

Future<void> _pump(WidgetTester tester, String url) async {
  await pumpLocalized(
    tester,
    Scaffold(
      body: Center(
        child: RemoteCircleAvatar(
          url: url,
          radius: 24,
          backgroundColor: Colors.white,
          fallback: const Icon(Icons.storefront_rounded, key: _fallback),
        ),
      ),
    ),
  );
  await settleFrames(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  testWidgets('no picture draws the fallback', (WidgetTester tester) async {
    await _pump(tester, '');

    expect(find.byKey(_fallback), findsOneWidget);
    expect(find.byKey(_picture), findsNothing);
  });

  testWidgets('a picture is drawn, cropped to the circle', (
    WidgetTester tester,
  ) async {
    _serve(_png);
    await _pump(tester, 'https://cdn.test/logo.png');

    final bool drawn = find.byKey(_picture).evaluate().isNotEmpty;
    final BoxFit? fit = drawn
        ? tester.widget<Image>(find.byKey(_picture)).fit
        : null;
    final bool clipped = find.byType(ClipOval).evaluate().isNotEmpty;
    _stopServing();

    expect(drawn, isTrue);
    expect(fit, BoxFit.cover);
    expect(clipped, isTrue);
  });

  testWidgets('a host that will not resolve falls back instead of throwing', (
    WidgetTester tester,
  ) async {
    _serve(_notAnImage);
    await _pump(tester, 'https://example.test/logo.png');

    final bool fellBack = find.byKey(_fallback).evaluate().isNotEmpty;
    final Object? thrown = tester.takeException();
    _stopServing();

    // The whole bug: this threw on every paint, for ever, and the circle
    // stayed blank with nothing to explain it.
    expect(thrown, isNull);
    expect(fellBack, isTrue);
  });

  testWidgets('it stops trying, rather than failing once per frame', (
    WidgetTester tester,
  ) async {
    _serve(_notAnImage);
    await _pump(tester, 'https://example.test/logo.png');

    // Several more frames after it has given up.
    await settleFrames(tester);
    await settleFrames(tester);

    final bool stillAsking = find.byKey(_picture).evaluate().isNotEmpty;
    final Object? thrown = tester.takeException();
    _stopServing();

    expect(stillAsking, isFalse);
    expect(thrown, isNull);
  });

  testWidgets('a new url is given a fresh attempt', (
    WidgetTester tester,
  ) async {
    // The old one failing says nothing about this one - a merchant who fixes a
    // broken logo must not have to restart the app to see it.
    _serve(_notAnImage);
    await _pump(tester, 'https://example.test/logo.png');
    expect(find.byKey(_picture), findsNothing);

    _serve(_png);
    await _pump(tester, 'https://cdn.test/new.png');

    final bool drawn = find.byKey(_picture).evaluate().isNotEmpty;
    _stopServing();

    expect(drawn, isTrue);
  });
}

class _Client implements HttpClient {
  final Uint8List payload;

  _Client(this.payload);

  @override
  bool autoUncompress = true;
  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = const Duration(seconds: 15);
  @override
  int? maxConnectionsPerHost;
  @override
  String? userAgent;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _Request(url, payload);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  @override
  final Uri uri;
  final Uint8List payload;

  _Request(this.uri, this.payload);

  @override
  final HttpHeaders headers = _Headers();

  @override
  Future<HttpClientResponse> close() async => _Response(payload);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  final Uint8List payload;

  _Response(this.payload);

  @override
  int get statusCode => HttpStatus.ok;
  @override
  int get contentLength => payload.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  HttpHeaders get headers => _Headers();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(payload).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
