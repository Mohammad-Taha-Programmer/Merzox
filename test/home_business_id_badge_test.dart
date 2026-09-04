import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/home/widgets/business_id_badge.dart';

Widget _testApp({required String id, double width = 82}) {
  return MaterialApp(
    builder: (BuildContext context, Widget? child) {
      return Directionality(textDirection: TextDirection.rtl, child: child!);
    },
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          height: 26,
          child: BusinessIdBadge(
            id: id,
            dialogTitle: 'Business identifier',
            copyLabel: 'Copy identifier',
            copiedMessage: 'Identifier copied',
            closeLabel: 'Close',
            tapHint: 'Show the complete identifier',
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'narrow ID badge opens a full selectable value without overflow',
    (WidgetTester tester) async {
      const id = 'MXB-LEGACY-LONG-IDENTIFIER';

      await tester.pumpWidget(_testApp(id: id, width: 64));

      expect(tester.takeException(), isNull);

      final badgeFinder = find.byKey(
        const ValueKey<String>('business-id-MXB-LEGACY-LONG-IDENTIFIER'),
      );

      expect(badgeFinder, findsOneWidget);

      await tester.tap(badgeFinder);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);

      expect(
        find.byKey(
          const ValueKey<String>('business-id-full-MXB-LEGACY-LONG-IDENTIFIER'),
        ),
        findsOneWidget,
      );

      expect(find.text(id), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('copy action writes only the raw ID without its visual prefix', (
    WidgetTester tester,
  ) async {
    const id = '54321';
    String? copiedText;

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    messenger.setMockMethodCallHandler(SystemChannels.platform, (
      MethodCall call,
    ) async {
      if (call.method == 'Clipboard.setData') {
        final arguments = call.arguments as Map<Object?, Object?>;

        copiedText = arguments['text'] as String?;
      }

      return null;
    });

    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(_testApp(id: id));

    await tester.tap(find.byKey(const ValueKey<String>('business-id-54321')));

    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('business-id-copy-54321')),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(copiedText, id);
    expect(copiedText, isNot('ID: 54321'));
    expect(find.text('Identifier copied'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'five-digit badge remains overflow-free in RTL at narrow widths',
    (WidgetTester tester) async {
      for (final width in <double>[58, 64, 82, 98]) {
        await tester.pumpWidget(_testApp(id: '54321', width: width));

        await tester.pump();

        expect(
          tester.takeException(),
          isNull,
          reason: 'badge width $width must not overflow',
        );
      }
    },
  );
}
