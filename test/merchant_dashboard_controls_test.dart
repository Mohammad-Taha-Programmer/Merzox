import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/constants/dates.dart';
import 'package:merzox/features/business/models/dashboard_period.dart';
import 'package:merzox/features/business/shell/widgets/merchant_dashboard_controls.dart';

import 'localization_test_harness.dart';

/// The three controls over the merchant's orders table.
///
/// The search field was drawn rather than built - a `readOnly` field with a
/// magnifier on it that a merchant could type into never, and tap forever. The
/// period button did nothing at all. The pager did not exist, so a table that
/// could hold a year of orders showed five.

final DateTime _today = DateTime(2026, 9, 16);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  group('the search field', () {
    testWidgets('it can be typed into at all', (WidgetTester tester) async {
      await pumpLocalized(
        tester,
        Scaffold(
          body: MerchantOrderSearchField(initialQuery: '', onSearch: (_) {}),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('merchantDashboard.search')),
        '222321',
      );
      await tester.pump();

      expect(find.text('222321'), findsOneWidget);
    });

    testWidgets('it reports the needle once typing stops', (
      WidgetTester tester,
    ) async {
      final List<String> reported = <String>[];

      await pumpLocalized(
        tester,
        Scaffold(
          body: MerchantOrderSearchField(
            initialQuery: '',
            settle: const Duration(milliseconds: 100),
            onSearch: reported.add,
          ),
        ),
      );

      final Finder field = find.byKey(
        const ValueKey<String>('merchantDashboard.search'),
      );

      // Four keystrokes in quick succession. Reporting each one would be four
      // requests for one search.
      for (final String value in <String>['2', '22', '222', '2223']) {
        await tester.enterText(field, value);
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(reported, isEmpty);

      await tester.pump(const Duration(milliseconds: 150));
      expect(reported, <String>['2223']);
    });

    testWidgets('the keyboard search key does not wait', (
      WidgetTester tester,
    ) async {
      final List<String> reported = <String>[];

      await pumpLocalized(
        tester,
        Scaffold(
          body: MerchantOrderSearchField(
            initialQuery: '',
            settle: const Duration(seconds: 30),
            onSearch: reported.add,
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('merchantDashboard.search')),
        '222321',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();

      expect(reported, <String>['222321']);
    });

    testWidgets('clearing it reports an empty needle at once', (
      WidgetTester tester,
    ) async {
      final List<String> reported = <String>[];

      await pumpLocalized(
        tester,
        Scaffold(
          body: MerchantOrderSearchField(
            initialQuery: 'ياسمين',
            onSearch: reported.add,
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('merchantDashboard.clearSearch')),
      );
      await tester.pump();

      expect(reported, <String>['']);
      expect(find.text('ياسمين'), findsNothing);
    });

    testWidgets('there is nothing to clear until something is typed', (
      WidgetTester tester,
    ) async {
      await pumpLocalized(
        tester,
        Scaffold(
          body: MerchantOrderSearchField(initialQuery: '', onSearch: (_) {}),
        ),
      );

      expect(
        find.byKey(const ValueKey<String>('merchantDashboard.clearSearch')),
        findsNothing,
      );
    });
  });

  group('the period button', () {
    Future<List<DashboardPeriod>> pumpButton(
      WidgetTester tester,
      DashboardPeriod period,
    ) async {
      final List<DashboardPeriod> chosen = <DashboardPeriod>[];

      await pumpLocalized(
        tester,
        Scaffold(
          body: MerchantPeriodButton(
            period: period,
            today: _today,
            onChanged: chosen.add,
          ),
        ),
      );

      return chosen;
    }

    testWidgets('it reads the period it is on', (WidgetTester tester) async {
      await pumpButton(tester, DashboardPeriod.currentMonth);

      expect(
        find.text('businessShell.periodCurrentMonth'.tr()),
        findsOneWidget,
      );
    });

    testWidgets('it offers every period, and a custom one', (
      WidgetTester tester,
    ) async {
      await pumpButton(tester, DashboardPeriod.currentMonth);
      await tester.tap(
        find.byKey(const ValueKey<String>('merchantDashboard.periodButton')),
      );
      await tester.pumpAndSettle();

      for (final DashboardPeriod option in DashboardPeriod.selectable) {
        expect(
          find.byKey(
            ValueKey<String>('merchantDashboard.period.${option.kind.name}'),
          ),
          findsOneWidget,
          reason: '${option.kind} is not offered',
        );
      }
      expect(
        find.byKey(const ValueKey<String>('merchantDashboard.period.custom')),
        findsOneWidget,
      );
    });

    testWidgets('choosing one reports it', (WidgetTester tester) async {
      final List<DashboardPeriod> chosen = await pumpButton(
        tester,
        DashboardPeriod.currentMonth,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('merchantDashboard.periodButton')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('merchantDashboard.period.lastWeek')),
      );
      await tester.pumpAndSettle();

      expect(chosen, <DashboardPeriod>[DashboardPeriod.lastWeek]);
    });

    testWidgets('a custom period reads as the days it covers', (
      WidgetTester tester,
    ) async {
      await pumpButton(
        tester,
        DashboardPeriod.custom(DateTime(2026, 3, 4), DateTime(2026, 5, 6)),
      );

      // Not "custom range": the merchant picked days and wants to see them,
      // in the one format every screen writes.
      expect(
        find.text(
          '${merzoxDay(DateTime(2026, 3, 4))} - '
          '${merzoxDay(DateTime(2026, 5, 6))}',
        ),
        findsOneWidget,
      );
    });
  });

  group('the pager', () {
    Future<List<int>> pumpPager(
      WidgetTester tester, {
      required int page,
      required int pageCount,
      required int total,
    }) async {
      final List<int> asked = <int>[];

      await pumpLocalized(
        tester,
        Scaffold(
          body: MerchantOrdersPager(
            page: page,
            pageCount: pageCount,
            total: total,
            onPage: asked.add,
          ),
        ),
      );

      return asked;
    }

    testWidgets('it says how much the period holds', (
      WidgetTester tester,
    ) async {
      await pumpPager(tester, page: 1, pageCount: 3, total: 130);

      expect(
        find.text('businessShell.ordersInPeriod'.tr(args: <String>['130'])),
        findsOneWidget,
      );
      expect(
        find.text('businessShell.pageOf'.tr(args: <String>['1', '3'])),
        findsOneWidget,
      );
    });

    testWidgets('one page needs no controls, only a count', (
      WidgetTester tester,
    ) async {
      await pumpPager(tester, page: 1, pageCount: 1, total: 12);

      expect(
        find.byKey(const ValueKey<String>('merchantDashboard.nextPage')),
        findsNothing,
      );
      expect(
        find.text('businessShell.ordersInPeriod'.tr(args: <String>['12'])),
        findsOneWidget,
      );
    });

    testWidgets('the ends of the range cannot be walked past', (
      WidgetTester tester,
    ) async {
      final List<int> first = await pumpPager(
        tester,
        page: 1,
        pageCount: 3,
        total: 130,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('merchantDashboard.previousPage')),
      );
      await tester.pump();
      expect(first, isEmpty);

      final List<int> last = await pumpPager(
        tester,
        page: 3,
        pageCount: 3,
        total: 130,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('merchantDashboard.nextPage')),
      );
      await tester.pump();
      expect(last, isEmpty);
    });

    testWidgets('it asks for the page either side', (
      WidgetTester tester,
    ) async {
      final List<int> asked = await pumpPager(
        tester,
        page: 2,
        pageCount: 3,
        total: 130,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('merchantDashboard.nextPage')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('merchantDashboard.previousPage')),
      );
      await tester.pump();

      expect(asked, <int>[3, 1]);
    });
  });
}
