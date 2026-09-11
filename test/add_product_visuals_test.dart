import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/core/widgets/merzox_icons.dart';
import 'package:merzox/features/business/products/merchant_product_editor_page.dart';
import 'package:merzox/features/business/products/merchant_product_options_dialog.dart';
import 'package:merzox/features/business/shell/business_bloc.dart';
import 'package:merzox/features/business/shell/merchant_product_images_page.dart';
import 'package:merzox/services/api_service.dart';

import 'golden/merzox_golden_harness.dart';

/// The add-product screen, against the artboard it is drawn from.
///
/// Two of these numbers were wrong in a way no assertion could see. The boxes
/// occupied the 48 the artboard asks for but PAINTED 18 of it - `constraints`
/// stretches the decorator while the outline keeps wrapping the text - so the
/// widget measured correct and the screen looked cramped, with an unexplained
/// gap under every field. So the height under test is the painted one, read
/// back out of the rendered pixels.

const double _xdFieldHeight = 48;
const double _xdDescriptionHeight = 115;

/// Reads the rendered surface and returns the rows where a field's border was
/// actually painted across the width.
Future<List<int>> _paintedBoxRows(WidgetTester tester) async {
  final ByteData data = (await tester.runAsync<ByteData>(() async {
    final RenderRepaintBoundary boundary =
        tester.renderObject(find.byKey(merzoxGoldenRootKey))
            as RenderRepaintBoundary;
    final ui.Image image = await boundary.toImage();
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  }))!;

  const int width = 375;
  const int height = 812;
  bool border(int x, int y) {
    final int i = (y * width + x) * 4;
    final int r = data.getUint8(i);
    final int g = data.getUint8(i + 1);
    final int b = data.getUint8(i + 2);
    // The board's #98C1D9, laid down at full ink.
    return (r - 152).abs() < 26 && (g - 193).abs() < 26 && (b - 217).abs() < 26;
  }

  final List<int> rows = <int>[];
  for (int y = 60; y < height - 40; y += 1) {
    int painted = 0;
    for (int x = 18; x < 357; x += 1) {
      if (border(x, y)) painted += 1;
    }
    if (painted > 200) rows.add(y);
  }

  return rows;
}

/// The colour actually laid down on one row of the rendered surface.
Future<Color> _borderColourAt(WidgetTester tester, int y) async {
  final ByteData data = (await tester.runAsync<ByteData>(() async {
    final RenderRepaintBoundary boundary =
        tester.renderObject(find.byKey(merzoxGoldenRootKey))
            as RenderRepaintBoundary;
    final ui.Image image = await boundary.toImage();
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  }))!;

  const int width = 375;
  final int i = (y * width + 100) * 4;

  return Color.fromARGB(
    255,
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
  );
}

class _NoProducts extends ApiService {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UploadingApi extends ApiService {
  final List<int> uploaded = <int>[];
  String url = 'https://cdn.test/product.jpg';
  bool refuse = false;

  @override
  Future<String> uploadProductImage({
    required String token,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    uploaded.add(bytes.length);
    if (refuse) throw StateError('offline');
    return url;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Session implements AuthSessionService {
  const _Session();

  @override
  Future<AuthSessionSnapshot> read() async =>
      const AuthSessionSnapshot(type: AuthSessionType.business, token: 'token');

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadMerzoxGoldenFonts();
    await loadMerzoxGoldenDateSymbols();
  });

  group('the artboard measurements', () {
    test('a single-line box is the height the board draws', () {
      expect(kProductFieldHeight, _xdFieldHeight);
    });

    test('the description box is the taller one the board draws', () {
      expect(kProductDescriptionHeight, _xdDescriptionHeight);
    });

    test('the content sits in the board own gutter', () {
      // 375 wide with a 16 gutter leaves the 343 every box on the board is.
      expect(375 - kProductGutter * 2, 343);
    });

    test('a tick box stands beside its label, not across the row', () {
      // The two used to be at opposite ends with the whole width between them,
      // which reads as two things on one line rather than as one control.
      expect(kCheckLabelGap, lessThan(kProductFieldHeight));
      expect(kCheckLabelGap, 10);
      expect(kCheckBoxSide, 18);
    });
  });

  group('the artboard palette', () {
    test('the outline is the board colour, at a weight a phone can show', () {
      expect(kProductOutline, MerzoxColors.kColor98C1D9);

      // The board says half a pixel. On a two-to-one screen that is a single
      // physical pixel, and a 48-tall run of it is invisible next to the
      // 328-wide run of the same line - the box arrives with no sides. A full
      // pixel is twice the ink on the edges that need it.
      expect(kProductOutlineWidth, greaterThanOrEqualTo(1));
    });

    test('a tick box is outlined in the darker blue, not the field blue', () {
      expect(kProductTickOutline, MerzoxColors.kColor3D5A80);
      expect(kProductTickFill, MerzoxColors.kColor3D5A80);
      expect(kProductTickOutline, isNot(kProductOutline));
    });

    test('the images panel dashes are the length the board sets', () {
      expect(kProductDash, 5);
    });
  });

  group('what the screen actually paints', () {
    testWidgets('every box paints the height it occupies', (
      WidgetTester tester,
    ) async {
      final TextEditingController controller = TextEditingController();
      addTearDown(controller.dispose);

      await pumpMerzoxGoldenPage(
        tester,
        withMerzoxGoldenDeviceInsets(
          Scaffold(
            backgroundColor: Colors.white,
            body: Padding(
              padding: const EdgeInsets.fromLTRB(
                kProductGutter,
                100,
                kProductGutter,
                0,
              ),
              child: Column(
                children: <Widget>[
                  ProductField(controller: controller, hint: 'اسم'),
                  const SizedBox(height: 40),
                  ProductField(
                    controller: controller,
                    hint: 'وصف',
                    height: kProductDescriptionHeight,
                    maxLines: 5,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final List<int> rows = await _paintedBoxRows(tester);

      expect(rows, hasLength(4));
      // The painted outline, not the space the widget was given: the two
      // disagreed by thirty pixels and only the paint is visible.
      expect(rows[1] - rows[0] + 1, _xdFieldHeight);
      expect(rows[3] - rows[2] + 1, _xdDescriptionHeight);

      // And the line is the board's own blue, not an approximation of it.
      final Color line = await _borderColourAt(tester, rows[0]);
      expect(line.r * 255, closeTo(152, 14));
      expect(line.g * 255, closeTo(193, 14));
      expect(line.b * 255, closeTo(217, 14));
    });

    testWidgets('an error message does not squeeze the box', (
      WidgetTester tester,
    ) async {
      final GlobalKey<FormState> form = GlobalKey<FormState>();
      final TextEditingController controller = TextEditingController();
      addTearDown(controller.dispose);

      await pumpMerzoxGoldenPage(
        tester,
        withMerzoxGoldenDeviceInsets(
          Scaffold(
            backgroundColor: Colors.white,
            body: Padding(
              padding: const EdgeInsets.fromLTRB(
                kProductGutter,
                100,
                kProductGutter,
                0,
              ),
              child: Form(
                key: form,
                child: ProductField(
                  controller: controller,
                  hint: 'اسم',
                  validator: (_) => 'مطلوب',
                ),
              ),
            ),
          ),
        ),
      );

      form.currentState!.validate();
      await settleMerzoxGoldenFrames(tester);

      // The obvious construction - a fixed-height box around the field -
      // gives the error nowhere to go and collapses the box to 28.
      expect(
        tester.getSize(find.byType(ProductField)).height,
        greaterThanOrEqualTo(_xdFieldHeight),
      );
    });
  }, skip: merzoxGoldenPlatformSkip);

  group('the tick box and its label', () {
    testWidgets('they sit together at the reading edge', (
      WidgetTester tester,
    ) async {
      await pumpMerzoxGoldenPage(
        tester,
        withMerzoxGoldenDeviceInsets(
          Scaffold(
            backgroundColor: Colors.white,
            body: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: kProductGutter,
                vertical: 100,
              ),
              child: ProductCheckRow(
                label: 'غير محدودة',
                value: false,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      final Rect label = tester.getRect(find.text('غير محدودة'));
      final Rect box = tester.getRect(find.byType(Container).first);

      // Reading right to left: the box first, the label a hair after it.
      expect(box.right, closeTo(375 - kProductGutter, 1));
      expect(box.left - label.right, closeTo(kCheckLabelGap, 1.5));
    });

    testWidgets('a ticked box is filled, an empty one is outlined', (
      WidgetTester tester,
    ) async {
      for (final bool ticked in <bool>[false, true]) {
        await pumpMerzoxGoldenPage(
          tester,
          withMerzoxGoldenDeviceInsets(
            Scaffold(
              body: Center(
                child: ProductCheckRow(
                  label: 'هناك تخفيض',
                  value: ticked,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        );

        final BoxDecoration decoration =
            tester.widget<Container>(find.byType(Container).first).decoration!
                as BoxDecoration;

        expect(
          decoration.color,
          ticked ? MerzoxColors.kColor3D5A80 : Colors.white,
        );
        expect(
          find.byIcon(Icons.check),
          ticked ? findsOneWidget : findsNothing,
        );
      }
    });

    testWidgets('tapping anywhere on the pair toggles it', (
      WidgetTester tester,
    ) async {
      bool value = false;

      await pumpMerzoxGoldenPage(
        tester,
        withMerzoxGoldenDeviceInsets(
          Scaffold(
            body: Center(
              child: ProductCheckRow(
                label: 'غير محدودة',
                value: value,
                onChanged: (bool next) => value = next,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('غير محدودة'));
      expect(value, isTrue);
    });
  }, skip: merzoxGoldenPlatformSkip);

  group('the options row under the description', () {
    testWidgets('the ring and its words stand together, not at two ends', (
      WidgetTester tester,
    ) async {
      await pumpMerzoxGoldenPage(
        tester,
        withMerzoxGoldenDeviceInsets(
          Scaffold(
            backgroundColor: Colors.white,
            body: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: kProductGutter,
                vertical: 100,
              ),
              child: ProductOptionsRow(count: 0, onPressed: () {}),
            ),
          ),
        ),
      );

      final Rect words = tester.getRect(find.text('إضافة خيارات أخرى'));
      final Rect ring = tester.getRect(find.byType(Container).first);

      // Reading right to left: the ring at the edge, the words just after.
      expect(ring.right, closeTo(375 - kProductGutter, 1));
      expect(ring.left - words.right, closeTo(kProductOptionsGap, 1.5));
    });
  }, skip: merzoxGoldenPlatformSkip);

  group('the options panel with a keyboard up', () {
    Future<void> pumpPanel(WidgetTester tester, double keyboard) async {
      await pumpMerzoxGoldenPage(
        tester,
        MediaQuery(
          data: MediaQueryData(
            size: merzoxGoldenSurfaceSize,
            devicePixelRatio: 1,
            padding: const EdgeInsets.only(top: 44),
            // What the phone reports once the keyboard is showing.
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: Navigator(
            onGenerateRoute: (RouteSettings settings) =>
                MaterialPageRoute<void>(
                  builder: (_) => ProductOptionsDialog(
                    options: const <ProductOptionDraft>[],
                    maxOptions: 12,
                    maxLabelLength: 40,
                  ),
                ),
          ),
        ),
      );
    }

    testWidgets('it does not overflow when the keyboard takes the room', (
      WidgetTester tester,
    ) async {
      // The panel is lifted clear of the keyboard, and what is left was not
      // enough to stand in: the column overflowed by 254 and most of the
      // panel went off screen, including the field being typed into.
      await pumpPanel(tester, 300);

      expect(tester.takeException(), isNull);
    });

    testWidgets('it keeps the room the keyboard left it', (
      WidgetTester tester,
    ) async {
      const double keyboard = 300;
      await pumpPanel(tester, keyboard);

      // The panel itself, not the full-screen widget that positions it.
      final double height = tester
          .getSize(
            find
                .descendant(
                  of: find.byType(ProductOptionsDialog),
                  matching: find.byType(Stack),
                )
                .first,
          )
          .height;

      // `Dialog` adds the view insets to whatever padding it is given, so
      // adding them again counted the keyboard twice: the panel collapsed to a
      // sliver at the top of the screen, open and focused and almost entirely
      // gone. What is left should be the screen less the board's own margins
      // and the keyboard - once.
      expect(height, closeTo(812 - 24 - 76 - keyboard, 24));
      expect(height, greaterThan(300));
    });

    testWidgets('what is left of it can be scrolled to', (
      WidgetTester tester,
    ) async {
      await pumpPanel(tester, 300);

      expect(find.byType(SingleChildScrollView), findsWidgets);
      expect(find.byType(ProductField), findsOneWidget);
    });

    testWidgets('with no keyboard it still fits without scrolling', (
      WidgetTester tester,
    ) async {
      await pumpPanel(tester, 0);

      expect(tester.takeException(), isNull);
      final ScrollableState scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(scrollable.position.maxScrollExtent, 0);
    });
  }, skip: merzoxGoldenPlatformSkip);

  group('adding a picture', () {
    Future<void> pumpImages(
      WidgetTester tester, {
      required ApiService api,
      Future<Uint8List?> Function(ImageSource)? pick,
    }) async {
      await pumpMerzoxGoldenPage(
        tester,
        withMerzoxGoldenDeviceInsets(
          MerchantProductImagesPage(
            imageUrls: const <String>[],
            apiService: api,
            authSessionService: const _Session(),
            pickImage: pick ?? (_) async => Uint8List.fromList(<int>[1, 2, 3]),
          ),
        ),
      );
    }

    testWidgets('the phone is offered, and so is a link', (
      WidgetTester tester,
    ) async {
      await pumpImages(tester, api: _NoProducts());

      await tester.tap(find.text('اسحب وأسقط الصور هنا'));
      await settleMerzoxGoldenFrames(tester);

      // A merchant who already hosts their catalogue elsewhere keeps the link;
      // one who has the jar in front of them gets the camera.
      expect(
        find.byKey(const ValueKey<String>('merchantImages.camera')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('merchantImages.gallery')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('merchantImages.link')),
        findsOneWidget,
      );
    });

    testWidgets('a picked photo is uploaded and its link kept', (
      WidgetTester tester,
    ) async {
      final _UploadingApi api = _UploadingApi();
      await pumpImages(tester, api: api);

      await tester.tap(find.text('اسحب وأسقط الصور هنا'));
      await settleMerzoxGoldenFrames(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('merchantImages.gallery')),
      );
      await settleMerzoxGoldenFrames(tester);

      // The bytes went to the server, and what came back is what a product
      // stores: a URL.
      expect(api.uploaded, <int>[3]);
      expect(find.byType(Image), findsWidgets);
    });

    testWidgets('a refused upload says so and adds nothing', (
      WidgetTester tester,
    ) async {
      final _UploadingApi api = _UploadingApi()..refuse = true;
      await pumpImages(tester, api: api);

      await tester.tap(find.text('اسحب وأسقط الصور هنا'));
      await settleMerzoxGoldenFrames(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('merchantImages.gallery')),
      );
      await settleMerzoxGoldenFrames(tester);

      // Silence would leave the merchant waiting for a picture that is never
      // coming.
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('a cancelled picker changes nothing', (
      WidgetTester tester,
    ) async {
      final _UploadingApi api = _UploadingApi();
      await pumpImages(tester, api: api, pick: (_) async => null);

      await tester.tap(find.text('اسحب وأسقط الصور هنا'));
      await settleMerzoxGoldenFrames(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('merchantImages.gallery')),
      );
      await settleMerzoxGoldenFrames(tester);

      expect(api.uploaded, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });
  }, skip: merzoxGoldenPlatformSkip);

  /// Three marks on this screen that no golden can see.
  ///
  /// `الصور` and the preview row sit below the product form's fold, and the
  /// lazy list never builds them for a capture; the variant sheet opens from a
  /// chip inside a dialog that is itself a capture. So the conversion of those
  /// three is asserted here, against the widgets the app ships, rather than
  /// left to a board that would never have shown it either way.
  group('the designer marks a merchant cannot see on a board', () {
    Future<void> pumpEditor(WidgetTester tester) async {
      final BusinessBloc bloc = BusinessBloc(apiService: _NoProducts());
      addTearDown(bloc.close);

      await pumpMerzoxGoldenPage(
        tester,
        BlocProvider<BusinessBloc>.value(
          value: bloc,
          child: withMerzoxGoldenDeviceInsets(const MerchantProductEditorPage()),
        ),
      );
    }

    testWidgets('the panel that takes pictures carries the designer cloud', (
      WidgetTester tester,
    ) async {
      await pumpEditor(tester);

      // The editor's own wording, which is not quite the image manager's:
      // `واسقط` here against `وأسقط` there, the same sentence spelled two ways
      // on two screens. Left as it is - it is a copy question, not this
      // branch's.
      await tester.scrollUntilVisible(
        find.text('اسحب واسقط الصور هنا'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await settleMerzoxGoldenFrames(tester);

      final Icon cloud = tester.widget<Icon>(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is Icon && widget.icon == MerzoxIcons.uploadProductImage,
        ),
      );

      // The number written on the screen is `42 * factor`, not the product of
      // the two: a reader of that line has to be able to see both the size the
      // board asks for and why it is not the size passed.
      expect(cloud.size, 42 * MerzoxIcons.uploadProductImageSizeFactor);
    });

    testWidgets('the preview row carries the designer eye', (
      WidgetTester tester,
    ) async {
      await pumpEditor(tester);

      await tester.scrollUntilVisible(
        find.text('معاينة'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await settleMerzoxGoldenFrames(tester);

      final Icon eye = tester.widget<Icon>(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is Icon && widget.icon == MerzoxIcons.previewProduct,
        ),
      );

      expect(eye.size, 18 * MerzoxIcons.previewProductSizeFactor);
    });

    testWidgets('removing a variant offers the designer bin', (
      WidgetTester tester,
    ) async {
      await pumpMerzoxGoldenPage(
        tester,
        withMerzoxGoldenDeviceInsets(
          Navigator(
            onGenerateRoute: (RouteSettings settings) =>
                MaterialPageRoute<void>(
                  builder: (_) => ProductOptionsDialog(
                    options: <ProductOptionDraft>[
                      ProductOptionDraft.named('أحمر'),
                    ],
                    maxOptions: 12,
                    maxLabelLength: 40,
                  ),
                ),
          ),
        ),
      );

      // The sheet is what a chip hides, so getting to the bin means opening
      // one.
      await tester.tap(find.text('أحمر'));
      await settleMerzoxGoldenFrames(tester);

      final Icon bin = tester.widget<Icon>(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is Icon &&
              widget.icon == MerzoxIcons.deleteProductForever,
        ),
      );

      expect(bin.size, 18 * MerzoxIcons.deleteProductSizeFactor);
    });
  }, skip: merzoxGoldenPlatformSkip);
}
