/// How Merzox writes a calendar day.
///
/// Seven screens each carried their own copy of this - two of them byte for
/// byte identical - and between them they used two different formats: the
/// order screens and the invoice wrote `15.2.2022`, the lists wrote
/// `15/2/2022`. One order shown two ways on two screens is a reader's problem,
/// not a style choice, so there is one format now and one place that writes it.
///
/// `2022/02/15`: year first, and both other parts padded. Padding matters more
/// than it looks - unpadded parts make a column of dates ragged, and `2022/2/5`
/// can be read as either the fifth of February or the second of May by someone
/// who does not already know the order.
library;

/// A calendar day as `2022/02/15`.
///
/// [whenMissing] is what a null date reads as. It defaults to a placeholder of
/// the same shape and width, so a column keeps its alignment when a date is
/// absent; a caller that would rather show nothing passes an empty string.
String merzoxDay(DateTime? value, {String whenMissing = '----/--/--'}) {
  if (value == null) return whenMissing;

  final DateTime local = value.toLocal();
  final String month = local.month.toString().padLeft(2, '0');
  final String day = local.day.toString().padLeft(2, '0');

  return '${local.year}/$month/$day';
}
