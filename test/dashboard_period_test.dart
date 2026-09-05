import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/business/models/dashboard_period.dart';

/// What each of the dashboard's periods actually asks the server for.
///
/// The control offers four named periods and a custom range, and the server
/// takes two calendar days, so the whole meaning of "this month" lives in the
/// translation between them. It is stated against a fixed day rather than the
/// clock, because a period that is only ever right on the day it was written
/// is not a period.

/// A Wednesday in the middle of a month, deliberately not the 1st or the last.
final DateTime _today = DateTime(2026, 9, 16, 14, 30);

String _d(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

void main() {
  test('this month runs from the first of the month to today', () {
    final DayRange days = DashboardPeriod.currentMonth.boundsOn(_today);

    expect(_d(days.from), '2026-09-01');
    expect(_d(days.to), '2026-09-16');
  });

  test('the rolling periods count back from today, today included', () {
    // A week is today and the six days before it. Counting seven back would
    // return eight days and call it a week.
    expect(_d(DashboardPeriod.lastWeek.boundsOn(_today).from), '2026-09-10');
    expect(_d(DashboardPeriod.lastWeek.boundsOn(_today).to), '2026-09-16');

    expect(_d(DashboardPeriod.lastMonth.boundsOn(_today).from), '2026-08-18');
    expect(_d(DashboardPeriod.year.boundsOn(_today).from), '2025-09-17');
  });

  test('a period never reaches past today', () {
    for (final DashboardPeriod period in DashboardPeriod.selectable) {
      final DayRange days = period.boundsOn(_today);

      expect(
        days.to.isAfter(DateTime(2026, 9, 16)),
        isFalse,
        reason: '${period.kind} asks for orders that cannot exist yet',
      );
      expect(days.from.isAfter(days.to), isFalse);
    }
  });

  test('the time of day is dropped: the server takes calendar days', () {
    final DayRange days = DashboardPeriod.currentMonth.boundsOn(_today);

    expect(days.to.hour, 0);
    expect(days.to.minute, 0);
    expect(days.from.hour, 0);
  });

  test('a custom range keeps the days it was given', () {
    final DashboardPeriod period = DashboardPeriod.custom(
      DateTime(2026, 3, 4),
      DateTime(2026, 5, 6),
    );
    final DayRange days = period.boundsOn(_today);

    expect(_d(days.from), '2026-03-04');
    expect(_d(days.to), '2026-05-06');
    expect(period.kind, DashboardPeriodKind.custom);
  });

  test('a custom range given back to front is put right, not refused', () {
    final DayRange days = DashboardPeriod.custom(
      DateTime(2026, 5, 6),
      DateTime(2026, 3, 4),
    ).boundsOn(_today);

    expect(_d(days.from), '2026-03-04');
    expect(_d(days.to), '2026-05-06');
  });

  test('the dashboard opens on this month', () {
    expect(DashboardPeriod.initial, DashboardPeriod.currentMonth);
    expect(DashboardPeriod.selectable.first, DashboardPeriod.currentMonth);
  });

  test('every period the control offers names itself', () {
    final Set<String> keys = <String>{
      for (final DashboardPeriod period in DashboardPeriod.selectable)
        period.labelKey,
      DashboardPeriod.custom(_today, _today).labelKey,
    };

    // Five periods, five distinct labels: two sharing one would make the
    // button unable to say which is on.
    expect(keys, hasLength(5));
    for (final String key in keys) {
      expect(key.startsWith('businessShell.period'), isTrue);
    }
  });
}
