/// The period the merchant dashboard is reporting on.
///
/// The board draws one control reading `الشهر الحالي` with a chevron, and it
/// governs both the three figures and the orders table under them. The server
/// takes two calendar days, so every period here has to resolve to a pair.
///
/// `الشهر الحالي` is a calendar period - the month so far - because that is
/// what a merchant means by "this month". The three that follow are rolling
/// windows counted back from today, because that is what `آخر` says: the last
/// week, not last week's calendar page. Mixing the two readings under one
/// control would make two adjacent options mean different kinds of thing.
enum DashboardPeriodKind { currentMonth, lastMonth, lastWeek, year, custom }

/// A calendar day, with no time of day: the server bounds `to` to the end of
/// the day it names, so a time here would be discarded anyway.
typedef DayRange = ({DateTime from, DateTime to});

final class DashboardPeriod {
  final DashboardPeriodKind kind;

  /// Set only for [DashboardPeriodKind.custom].
  final DateTime? customFrom;
  final DateTime? customTo;

  const DashboardPeriod._(this.kind, {this.customFrom, this.customTo});

  static const DashboardPeriod currentMonth = DashboardPeriod._(
    DashboardPeriodKind.currentMonth,
  );
  static const DashboardPeriod lastMonth = DashboardPeriod._(
    DashboardPeriodKind.lastMonth,
  );
  static const DashboardPeriod lastWeek = DashboardPeriod._(
    DashboardPeriodKind.lastWeek,
  );
  static const DashboardPeriod year = DashboardPeriod._(
    DashboardPeriodKind.year,
  );

  /// The days the merchant picked. Given back to front, they are put right
  /// rather than refused: a range is a range whichever end was tapped first.
  factory DashboardPeriod.custom(DateTime from, DateTime to) {
    final DateTime a = _day(from);
    final DateTime b = _day(to);
    return a.isAfter(b)
        ? DashboardPeriod._(
            DashboardPeriodKind.custom,
            customFrom: b,
            customTo: a,
          )
        : DashboardPeriod._(
            DashboardPeriodKind.custom,
            customFrom: a,
            customTo: b,
          );
  }

  /// The choices the control offers, in the order it lists them.
  static const List<DashboardPeriod> selectable = <DashboardPeriod>[
    currentMonth,
    lastMonth,
    lastWeek,
    year,
  ];

  static const DashboardPeriod initial = currentMonth;

  String get labelKey => switch (kind) {
    DashboardPeriodKind.currentMonth => 'businessShell.periodCurrentMonth',
    DashboardPeriodKind.lastMonth => 'businessShell.periodLastMonth',
    DashboardPeriodKind.lastWeek => 'businessShell.periodLastWeek',
    DashboardPeriodKind.year => 'businessShell.periodYear',
    DashboardPeriodKind.custom => 'businessShell.periodCustom',
  };

  /// The two days to send, resolved against [today].
  ///
  /// [today] is passed rather than read from the clock so this is a function
  /// of its input and a test can state what "this month" means on a given day.
  DayRange boundsOn(DateTime today) {
    final DateTime end = _day(today);

    return switch (kind) {
      DashboardPeriodKind.currentMonth => (
        from: DateTime(end.year, end.month),
        to: end,
      ),
      // Rolling windows. The end day counts as one of them, so a week is today
      // and the six days before it, not today and seven more.
      DashboardPeriodKind.lastMonth => (
        from: end.subtract(const Duration(days: 29)),
        to: end,
      ),
      DashboardPeriodKind.lastWeek => (
        from: end.subtract(const Duration(days: 6)),
        to: end,
      ),
      DashboardPeriodKind.year => (
        from: end.subtract(const Duration(days: 364)),
        to: end,
      ),
      DashboardPeriodKind.custom => (
        from: customFrom ?? end,
        to: customTo ?? end,
      ),
    };
  }

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  @override
  bool operator ==(Object other) =>
      other is DashboardPeriod &&
      other.kind == kind &&
      other.customFrom == customFrom &&
      other.customTo == customTo;

  @override
  int get hashCode => Object.hash(kind, customFrom, customTo);
}
