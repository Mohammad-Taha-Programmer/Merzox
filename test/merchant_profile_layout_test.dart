import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/features/business/shell/business_shell_page.dart';

import 'golden/merzox_golden_harness.dart';

/// The merchant profile, against the board it is drawn from.
///
/// The screen was a flat white list under a 62-tall band. The board draws a
/// blue field with a white sheet lifted onto it, the shop's picture set in a
/// ring on that sheet, a customer button under the name, and rows that carry
/// their icon at the reading edge with the chevron alone at the far one - the
/// mirror of what the screen had.
///
/// The measurements below are the board's own, and the rendered screen lands
/// on every one of them.

/// The board's y positions, counted from the top of the status bar.
const double _xdSheetTop = 113;
const List<double> _xdRowTops = <double>[302, 366, 430, 494, 558, 622];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the measurements the board sets', () {
    test('the sheet is lifted onto the field, not butted against it', () {
      // A strip of blue between the title and the sheet is what makes it read
      // as lifted rather than as a background change.
      expect(kProfileSheetRadius, 20);
      expect(kProfileSheetGap, greaterThan(0));
    });

    test('the field is wider than the board draws it, deliberately', () {
      // The board puts the sheet's edge at 113 and the screen was built to it
      // exactly. The reader looked at both and asked for more blue above the
      // picture, so this is a decision rather than a measurement - recorded
      // here so nobody later "corrects" it back to the board.
      const double drawn = 44 + kProfileTitleBand + kProfileSheetGap;

      expect(drawn, greaterThan(_xdSheetTop));
      expect(drawn - _xdSheetTop, 20);
    });

    test('the rows are the board size, at the board pitch', () {
      expect(kProfileRowHeight, 48);
      expect(kProfileRowRadius, 6);
      expect(kProfileGutter, 16);

      // 48 tall with 16 between them is the 64 the board repeats.
      expect(kProfileRowHeight + kProfileRowGap, 64);
      for (int i = 1; i < _xdRowTops.length; i += 1) {
        expect(_xdRowTops[i] - _xdRowTops[i - 1], 64);
      }
    });

    test('the picture is the small one the board sets, with its ring', () {
      // It used to be a 52 circle with no ring, which read as a different
      // element entirely.
      expect(kProfileAvatarDiameter, 37);
      expect(kProfileAvatarRing, 5);
      expect(375 - kProfileGutter * 2, 343);
    });
  });

  group('what the screen paints', () {
    testWidgets('a row carries its icon at the reading edge', (
      WidgetTester tester,
    ) async {
      await pumpMerzoxGoldenPage(
        tester,
        withMerzoxGoldenDeviceInsets(
          Scaffold(
            backgroundColor: Colors.white,
            body: Padding(
              padding: const EdgeInsets.only(top: 100),
              child: MerchantProfileMenuRow(
                icon: Icons.person_outline_rounded,
                label: 'الملف الشخصي',
                showChevron: true,
                onTap: () {},
              ),
            ),
          ),
        ),
      );

      final Rect icon = tester.getRect(
        find.byIcon(Icons.person_outline_rounded),
      );
      final Rect chevron = tester.getRect(
        find.byIcon(Icons.chevron_right_rounded),
      );
      final Rect label = tester.getRect(find.text('الملف الشخصي'));

      // Reading right to left: icon, then the words, and the chevron alone
      // at the far end. The screen had these two the other way round.
      expect(icon.center.dx, greaterThan(label.center.dx));
      expect(chevron.center.dx, lessThan(label.center.dx));
      expect(icon.right, closeTo(375 - kProfileGutter - 14, 2));

      // And it leans the way the board draws it. The chevron is named for
      // where the row goes, and Material turns it for the reading; naming the
      // left one turned it twice and left it pointing back at the words.
      expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
      expect(
        tester
            .widget<Icon>(find.byIcon(Icons.chevron_right_rounded))
            .icon!
            .matchTextDirection,
        isTrue,
      );
    });

    testWidgets('a row without a screen behind it carries no chevron', (
      WidgetTester tester,
    ) async {
      await pumpMerzoxGoldenPage(
        tester,
        withMerzoxGoldenDeviceInsets(
          Scaffold(
            body: Padding(
              padding: const EdgeInsets.only(top: 100),
              child: MerchantProfileMenuRow(
                icon: Icons.phone_outlined,
                label: 'تواصل معنا',
                onTap: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    });

    testWidgets('a row grows with the reader font rather than clipping', (
      WidgetTester tester,
    ) async {
      Future<double> heightAt(
        double scale, {
        String label = 'تواصل معنا',
      }) async {
        await pumpMerzoxGoldenPage(
          tester,
          MediaQuery(
            data: MediaQueryData(
              size: merzoxGoldenSurfaceSize,
              devicePixelRatio: 1,
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: MerchantProfileMenuRow(
                icon: Icons.phone_outlined,
                label: label,
                onTap: () {},
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        return tester.getSize(find.byType(MerchantProfileMenuRow)).height;
      }

      // The card on the products screen overflowed for exactly this reason;
      // these rows are built with a floor instead of a fixed height.
      final double plain = await heightAt(1);
      expect(plain, closeTo(kProfileRowHeight + kProfileRowGap, 0.5));

      // A short label still fits at the reader's own 1.3, so the row keeps the
      // board's height - the point is that it does not burst, not that it
      // moves for its own sake.
      expect(
        await heightAt(1.3),
        closeTo(kProfileRowHeight + kProfileRowGap, 0.5),
      );

      // Give it more than the box holds and it takes the room instead of
      // printing the stripe.
      final double stretched = await heightAt(
        2,
        label: 'تواصل معنا عبر البريد أو الهاتف في أي وقت خلال ساعات العمل',
      );
      expect(stretched, greaterThan(plain));
    });

    testWidgets('the row is the board colour, not the old grey', (
      WidgetTester tester,
    ) async {
      await pumpMerzoxGoldenPage(
        tester,
        withMerzoxGoldenDeviceInsets(
          Scaffold(
            body: Padding(
              padding: const EdgeInsets.only(top: 100),
              child: MerchantProfileMenuRow(
                icon: Icons.phone_outlined,
                label: 'تواصل معنا',
                onTap: () {},
              ),
            ),
          ),
        ),
      );

      final Material row = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(MerchantProfileMenuRow),
              matching: find.byType(Material),
            )
            .first,
      );

      expect(row.color, MerzoxColors.kColorF5F9FC);
    });
  }, skip: merzoxGoldenPlatformSkip);
}
