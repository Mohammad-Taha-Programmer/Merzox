/// How Merzox writes an amount of money.
///
/// A price is not a count. `toStringAsFixed(0)` rounds 5.5 to `6`, which shows
/// the customer a number that is not the price they will pay - and rounds up
/// as often as down, so it is not even conservatively wrong. Six screens did
/// that; two others already carried their own correct copy of the rule.
///
/// The rule itself: show the decimals when the amount has them, and leave them
/// off when it does not, so a whole 65 stays `65` rather than becoming `65.00`.
/// Nothing here is locale-aware yet - the digits are the same in both shipped
/// locales, and inventing a separator policy without a design for one would be
/// a guess.
library;

/// The bare amount, with no currency mark.
///
/// Two decimals at most: money in this system is stored to the agora, and a
/// longer tail would be a floating-point artefact rather than a real price.
String merzoxAmount(num value) {
  final double amount = value.toDouble();

  if (!amount.isFinite) return '0';
  if (amount == amount.roundToDouble()) return amount.toStringAsFixed(0);

  final String withDecimals = amount.toStringAsFixed(2);

  // `5.50` reads as machine output; `5.5` is what the artboards write.
  return withDecimals.endsWith('0')
      ? withDecimals.substring(0, withDecimals.length - 1)
      : withDecimals;
}

/// The sign this app writes prices in.
const String merzoxCurrencySign = '₪';

/// An amount with its currency, which is what a reader needs.
///
/// A bare figure under a heading like `السعر` is a number without a unit, and
/// a merchant reading a column of them has to be told which currency they are
/// in. Screens were each appending the sign themselves, so the spacing and the
/// order were one edit away from disagreeing between two screens showing the
/// same order.
String merzoxPrice(num value) => '${merzoxAmount(value)} $merzoxCurrencySign';
