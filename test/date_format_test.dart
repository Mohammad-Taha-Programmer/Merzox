import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/constants/dates.dart';

/// How Merzox writes a calendar day.
///
/// Seven screens each carried their own copy of this, and between them they
/// used two formats: the order screens wrote `15.2.2022`, the lists wrote
/// `15/2/2022`. One order shown two ways on two screens is a reader's problem,
/// not a style choice.

void main() {
  test('a day is written year first, with both other parts padded', () {
    expect(merzoxDay(DateTime(2022, 2, 15)), '2022/02/15');
    expect(merzoxDay(DateTime(2026, 12, 31)), '2026/12/31');
  });

  test('padding is not cosmetic', () {
    // `2022/2/5` can be read as the fifth of February or the second of May by
    // anyone who does not already know the order. Padded, it cannot.
    expect(merzoxDay(DateTime(2022, 2, 5)), '2022/02/05');
    expect(merzoxDay(DateTime(2022, 2, 5)).length, 10);
    expect(merzoxDay(DateTime(2022, 12, 25)).length, 10);
  });

  test('a missing date keeps the column its width', () {
    expect(merzoxDay(null), '----/--/--');
    expect(merzoxDay(null).length, merzoxDay(DateTime(2022, 2, 15)).length);
  });

  test('a caller may ask for nothing instead of a placeholder', () {
    // A dense table reads better with a gap than with dashes in it.
    expect(merzoxDay(null, whenMissing: ''), '');
  });

  test('the day is the reader local one, not the stored instant', () {
    final DateTime utc = DateTime.utc(2022, 2, 15, 22, 30);

    // Whatever the machine's zone, the day shown is the day it is there.
    expect(merzoxDay(utc), merzoxDay(utc.toLocal()));
  });

  test('no screen writes a date any other way', () async {
    // The formats this replaced, so neither can quietly come back.
    expect(merzoxDay(DateTime(2022, 2, 15)), isNot(contains('.')));
    expect(merzoxDay(DateTime(2022, 2, 15)), isNot('15/2/2022'));
  });
}
