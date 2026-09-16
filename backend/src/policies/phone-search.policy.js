/**
 * Finding a shop by the number its owner answers on.
 *
 * A customer often has the merchant's number and not their shop's name - it
 * was written on a receipt, or a neighbour sent it. The number is the one thing
 * about a shop that is never spelled two ways, so it is the one search that
 * cannot be defeated by a hamza.
 *
 * The difficulty is that one number has several spellings too, in a different
 * sense: `0592029316`, `+970592029316` and `00970592029316` are the same
 * telephone. The account stores one of them and the customer types another.
 */

/** Everything that is not a digit, gone. */
function digitsOf(value) {
  return String(value ?? '').replace(/\D/g, '');
}

/**
 * The shortest tail of digits two spellings of one number must share.
 *
 * Seven, which is a local number in this region. Shorter than that and a
 * search for `083` would find every shop whose owner's number happens to end
 * in those digits - which is most of the point of a phone search thrown away.
 */
export const PHONE_MIN_DIGITS = 7;

/**
 * The digits to look a number up by, or null when this is not a number.
 *
 * What comes off is everything that identifies the country rather than the
 * subscriber: the `00` or `+` a customer may or may not have typed, and the
 * trunk zero that belongs to dialling inside the country. What is left is the
 * part that is the same however the number was written down.
 */
export function phoneSearchDigits(query) {
  const raw = String(query ?? '').trim();

  // Letters mean this is a name that happens to contain digits, not a number.
  if (/[^\d\s+()\-.]/.test(raw)) return null;

  let digits = digitsOf(raw);
  if (digits.startsWith('00')) digits = digits.slice(2);
  if (digits.startsWith('0')) digits = digits.slice(1);

  return digits.length >= PHONE_MIN_DIGITS ? digits : null;
}

/**
 * Whether a stored number is the one being looked for.
 *
 * Compared from the right: the customer may have typed the local form of a
 * number the account stores internationally, or the other way round, and the
 * end of a telephone number is the part that does not change.
 */
export function phoneMatches(stored, digits) {
  if (!digits) return false;

  const held = digitsOf(stored);
  if (held.length < PHONE_MIN_DIGITS) return false;

  return held.endsWith(digits) || digits.endsWith(held);
}

/**
 * A pattern that finds those numbers in the database.
 *
 * Anchored at the end, and tolerant of the separators an account may have been
 * saved with - a number stored as `+970 59 202 9316` is the same number.
 *
 * Built from characters and classes PCRE reads the same way JavaScript does,
 * for the reason the Arabic one carries at length: these patterns are executed
 * by MongoDB, not here.
 */
export function phoneSearchPattern(digits) {
  if (!digits) return null;

  const separators = '[^0-9]*';
  const body = digits.split('').join(separators);

  return new RegExp(`${body}${separators}$`);
}
