import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/constants/money.dart';

void main() {
  group('merzoxAmount', () {
    test('a whole amount keeps no decimals', () {
      expect(merzoxAmount(65), '65');
      expect(merzoxAmount(0), '0');
      expect(merzoxAmount(1200), '1200');
      expect(merzoxAmount(5.0), '5');
    });

    test('a fractional amount is never rounded away', () {
      // The defect this replaced: toStringAsFixed(0) showed a 5.5 product as
      // `6`, a price the customer would not be charged.
      expect(merzoxAmount(5.5), '5.5');
      expect(merzoxAmount(0.5), '0.5');
      expect(merzoxAmount(19.99), '19.99');
      expect(merzoxAmount(4.49), '4.49');
    });

    test(
      'a trailing zero is dropped, so it reads as a price not a machine',
      () {
        expect(merzoxAmount(5.50), '5.5');
        expect(merzoxAmount(12.10), '12.1');
      },
    );

    test('the tail stops at the agora', () {
      // Two decimals at most: a longer tail would be a floating-point artefact
      // rather than a price anyone can be charged.
      //
      // 5.555 renders as 5.55, not 5.56: the nearest double to 5.555 is
      // slightly BELOW it, so rounding it down is the arithmetic being
      // truthful about the value it was actually given.
      expect(merzoxAmount(5.555), '5.55');
      expect(merzoxAmount(1 / 3), '0.33');
      expect(merzoxAmount(2.675), '2.67');
    });

    test('a non-finite amount degrades instead of printing Infinity', () {
      expect(merzoxAmount(double.infinity), '0');
      expect(merzoxAmount(double.nan), '0');
    });

    test('it never rounds a price upward', () {
      // Every fractional amount must render at least as much precision as it
      // has; the old formatter rounded 5.5 up to 6 and 5.4 down to 5.
      for (final double amount in <double>[5.4, 5.5, 5.6, 0.01, 99.9]) {
        expect(double.parse(merzoxAmount(amount)), closeTo(amount, 0.005));
      }
    });
  });

  group('an amount with its currency', () {
    test('it is the amount and the sign, in that order', () {
      expect(merzoxPrice(45), '45 $merzoxCurrencySign');
      expect(merzoxPrice(5.5), '5.5 $merzoxCurrencySign');
      expect(merzoxPrice(0), '0 $merzoxCurrencySign');
    });

    test('it formats the figure exactly as the bare helper does', () {
      // One rule for how money reads, not two that can drift apart.
      for (final num amount in <num>[0, 1, 5.5, 99.99, 1234, 0.01]) {
        expect(merzoxPrice(amount), startsWith(merzoxAmount(amount)));
        expect(merzoxPrice(amount), endsWith(merzoxCurrencySign));
      }
    });

    test('the sign is the shekel this app prices in', () {
      expect(merzoxCurrencySign, '₪');
    });
  });
}
