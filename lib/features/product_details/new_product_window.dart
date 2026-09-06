/// How long a product counts as newly added.
///
/// The shop already has a `الجديدة` shelf, but that is a shelf: the merchant
/// puts a product on it and it stays there until they move it. This is about
/// age - a product that went up this week - so it appears on its own and goes
/// away on its own, and nobody has to remember to take it down.
library;

/// A week, as the reader asked for it.
const Duration kNewProductWindow = Duration(days: 7);

/// Whether a product added at [addedAt] is still new as of [now].
///
/// A product with no date is not new. That is not a formality: an older row
/// that predates the field, or a payload that dropped it, would otherwise wear
/// the mark for ever - which is exactly the failure a time-limited badge
/// exists to avoid.
///
/// A date in the future counts as new. It means a clock somewhere is off by a
/// little, and the honest reading of "added tomorrow" is "just added".
bool productIsNewlyAdded(DateTime? addedAt, {required DateTime now}) {
  if (addedAt == null) return false;

  final Duration age = now.difference(addedAt.toLocal());

  if (age.isNegative) return true;

  return age < kNewProductWindow;
}
