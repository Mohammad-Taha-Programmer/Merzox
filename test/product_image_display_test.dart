import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/business_profile/pages/business_profile_page.dart';
import 'package:merzox/features/product_details/pages/product_details_page.dart';
import 'package:merzox/services/api_service.dart';

import 'localization_test_harness.dart';

/// A picture the merchant attached, arriving where a customer looks.
///
/// Three ways in - a photo from the phone now on the image host, one taken
/// with the camera, or a link pasted by hand - and all three end as the same
/// thing: a URL on the product. So what has to hold is that the URL the
/// merchant saved is the URL the shop's card draws and the URL the slider at
/// the head of the product pages through.
///
/// The wire half of this was checked against the running server: an image
/// uploaded through the endpoint came back on `/businesses/:id/products` and
/// on `/businesses/:id/products/:id` with no session at all. What follows is
/// the half that runs in the app.

/// A URL of the exact shape the image host returns.
const String _hosted =
    'https://res.cloudinary.com/dckzcs3ix/image/upload/v1788699735/merzox/products/drin5zazlue9v78bldek.png';
const String _pasted = 'https://example.com/lipstick.jpg';

BusinessProductApiModel _product({
  List<String> imageUrls = const <String>[],
  String imageUrl = '',
}) {
  return BusinessProductApiModel.fromJson(<String, dynamic>{
    'id': 'p1',
    'name': 'أحمر الشفاه',
    'price': 5,
    'finalPrice': 5,
    'inStock': true,
    'hasVariants': false,
    'minPrice': 5,
    'maxPrice': 5,
    'minFinalPrice': 5,
    'maxFinalPrice': 5,
    'discountPercent': 0,
    'variants': <dynamic>[],
    'imageUrls': imageUrls,
    'imageUrl': imageUrl,
  });
}

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

/// Bytes that are not an image: what a link that has rotted looks like here.
final Uint8List _notAnImage = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);

void _serve(Uint8List payload) {
  debugNetworkImageHttpClientProvider = () => _Client(payload);
}

void _stopServing() {
  debugNetworkImageHttpClientProvider = null;
  PaintingBinding.instance.imageCache.clear();
  PaintingBinding.instance.imageCache.clearLiveImages();
}

String? _requestedUrl(WidgetTester tester) {
  final Finder image = find.byType(Image);
  if (image.evaluate().isEmpty) return null;

  final ImageProvider provider = tester.widget<Image>(image.first).image;
  return provider is NetworkImage ? provider.url : null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  group('which pictures the product has', () {
    test('an uploaded photo survives the wire as a plain url', () {
      // Nothing about the image host is special to the product: what comes
      // back from the upload is a link, and a link is all a product stores.
      expect(_product(imageUrls: <String>[_hosted]).imageUrls, <String>[
        _hosted,
      ]);
      expect(_product(imageUrls: <String>[_hosted]).imageUrl, _hosted);
    });

    test('the slider pages through every picture, in the saved order', () {
      final BusinessProductApiModel product = _product(
        imageUrls: <String>[_hosted, _pasted],
      );

      expect(productGallery(product), <String>[_hosted, _pasted]);
      // The card shows the first, so both screens agree which picture the
      // product "is".
      expect(product.imageUrl, _hosted);
    });

    test('a product saved before galleries existed still shows its one', () {
      final BusinessProductApiModel product = _product(imageUrl: _pasted);

      expect(productGallery(product), <String>[_pasted]);
    });

    test('a product with no picture pages through empty frames', () {
      // Rather than collapsing the slider to nothing, which is not what the
      // artboard draws.
      expect(productGallery(_product()), <String>['', '', '']);
    });

    test('the same url is not paged through twice', () {
      // The server folds the older single field into the list; a client that
      // appended it again would give the slider a duplicate frame.
      final BusinessProductApiModel product = _product(
        imageUrls: <String>[_hosted],
        imageUrl: _hosted,
      );

      expect(productGallery(product), <String>[_hosted]);
    });
  });

  group('the card in the shop profile', () {
    testWidgets('it asks for the url the merchant saved', (
      WidgetTester tester,
    ) async {
      _serve(_png);
      await pumpLocalized(
        tester,
        const Scaffold(
          body: SizedBox(
            width: 150,
            height: 150,
            child: ProductCardImage(imageUrl: _hosted),
          ),
        ),
      );

      final String? asked = _requestedUrl(tester);
      _stopServing();

      expect(asked, _hosted);
    });

    testWidgets('a pasted link is drawn the same way', (
      WidgetTester tester,
    ) async {
      _serve(_png);
      await pumpLocalized(
        tester,
        const Scaffold(
          body: SizedBox(
            width: 150,
            height: 150,
            child: ProductCardImage(imageUrl: _pasted),
          ),
        ),
      );

      final String? asked = _requestedUrl(tester);
      _stopServing();

      expect(asked, _pasted);
    });

    testWidgets('no picture draws the placeholder, not an empty request', (
      WidgetTester tester,
    ) async {
      await pumpLocalized(
        tester,
        const Scaffold(
          body: SizedBox(
            width: 150,
            height: 150,
            child: ProductCardImage(imageUrl: ''),
          ),
        ),
      );

      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.shopping_bag_outlined), findsOneWidget);
    });

    testWidgets('a link that has rotted falls back instead of throwing', (
      WidgetTester tester,
    ) async {
      _serve(_notAnImage);
      await pumpLocalized(
        tester,
        const Scaffold(
          body: SizedBox(
            width: 150,
            height: 150,
            child: ProductCardImage(imageUrl: _pasted),
          ),
        ),
      );
      await settleFrames(tester);

      final bool fellBack = find
          .byIcon(Icons.shopping_bag_outlined)
          .evaluate()
          .isNotEmpty;
      final Object? thrown = tester.takeException();
      _stopServing();

      // The card had no error builder at all: a link that had rotted threw on
      // every paint and left the customer with a broken card and no idea why.
      expect(thrown, isNull);
      expect(fellBack, isTrue);
    });
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
