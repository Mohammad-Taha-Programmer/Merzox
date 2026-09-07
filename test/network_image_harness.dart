import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Serving an image to `Image.network` inside a widget test.
///
/// `HttpOverrides` is the wrong seam: Flutter keeps one shared client for
/// network images and builds it once, so the second test in a file would be
/// served by the first test's override. `debugNetworkImageHttpClientProvider`
/// is the seam the framework provides for exactly that reason.

/// A one-pixel PNG, so `Image.network` has something real to decode.
final Uint8List merzoxPixelPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// Bytes that are not an image: what a dead or replaced image host looks like
/// from here — the request succeeds and the decode does not.
final Uint8List merzoxNotAnImage = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);

/// Serves [payload] to any image request.
void serveNetworkImage([Uint8List? payload]) {
  debugNetworkImageHttpClientProvider = () =>
      _PixelClient(payload: payload ?? merzoxPixelPng);
}

/// Puts the seam back.
///
/// This has to run inside the test body, not in a teardown: `testWidgets`
/// asserts that no painting debug variable outlived the test, and it checks
/// that before any teardown gets to run.
void stopServingNetworkImages() {
  debugNetworkImageHttpClientProvider = null;
  PaintingBinding.instance.imageCache.clear();
  PaintingBinding.instance.imageCache.clearLiveImages();
}

class _PixelClient implements HttpClient {
  final Uint8List payload;

  _PixelClient({Uint8List? payload}) : payload = payload ?? merzoxPixelPng;

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
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _PixelRequest(url, payload);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PixelRequest implements HttpClientRequest {
  @override
  final Uri uri;
  final Uint8List payload;

  _PixelRequest(this.uri, this.payload);

  @override
  final HttpHeaders headers = _NoHeaders();

  @override
  Future<HttpClientResponse> close() async => _PixelResponse(payload);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PixelResponse extends Stream<List<int>> implements HttpClientResponse {
  final Uint8List payload;

  _PixelResponse(this.payload);

  @override
  int get statusCode => HttpStatus.ok;
  @override
  int get contentLength => payload.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  HttpHeaders get headers => _NoHeaders();

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

class _NoHeaders implements HttpHeaders {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
