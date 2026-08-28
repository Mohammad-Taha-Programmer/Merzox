/**
 * Date of birth is a DATE-ONLY value.
 *
 * The canonical wire representation is `YYYY-MM-DD`. It is deliberately not a
 * timestamp: a birth date is a calendar fact, and no timezone conversion may be
 * allowed to shift it by a day. Storage normalizes to UTC midnight so the
 * stored instant and the exposed calendar date can never disagree.
 *
 * The field is optional. There is no minimum age, no adult-only policy, no
 * maximum age and no one-time-change restriction here; the only semantic
 * restrictions are shape, calendar reality and "not in the future". Every year
 * the canonical shape can express — 0001 through 9999 — is read as that literal
 * Gregorian year, so the backend accepts exactly the range the year selector
 * offers.
 */

export const BIRTH_DATE_ERRORS = {
  invalid: 'INVALID_BIRTH_DATE'
};

/** Strict canonical shape. No trimming: a padded value is not canonical. */
const canonicalPattern = /^(\d{4})-(\d{2})-(\d{2})$/;

/**
 * UTC midnight on a literal Gregorian year/month/day.
 *
 * `Date.UTC(year, ...)` cannot be used here: it maps years 0-99 into the
 * 1900-1999 window, so `0001-01-01` would silently become 1901 and `0099-12-31`
 * 1999. Setting the components on an epoch-based `Date` through
 * `setUTCFullYear` has no such window, so every year 1-9999 keeps its literal
 * value. The epoch base is already 00:00:00.000Z, so the result is UTC
 * midnight.
 */
function utcMidnight(year, month, day) {
  const date = new Date(0);

  date.setUTCFullYear(year, month - 1, day);

  return date;
}

/**
 * The UTC-midnight `Date` a canonical birth date denotes, or `null` when the
 * value is not a real, non-future Gregorian calendar date.
 *
 * Validation is by calendar component round-trip rather than by
 * `new Date(value)`, because JavaScript silently normalizes impossible dates
 * (`2026-02-30` becomes March 2nd) and would otherwise accept them.
 */
export function parseBirthDate(value, { now = new Date() } = {}) {
  if (typeof value !== 'string') {
    return null;
  }

  const match = canonicalPattern.exec(value);

  if (!match) {
    return null;
  }

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);

  // Year 0000 is not a Gregorian year anybody was born in, and the canonical
  // shape caps the range at 9999.
  if (year < 1 || month < 1 || month > 12 || day < 1 || day > 31) {
    return null;
  }

  const parsed = utcMidnight(year, month, day);

  // Rejects impossible days: 2025-02-29 and 0001-02-29 both roll into March.
  if (
    parsed.getUTCFullYear() !== year ||
    parsed.getUTCMonth() !== month - 1 ||
    parsed.getUTCDate() !== day
  ) {
    return null;
  }

  const today = utcMidnight(
    now.getUTCFullYear(),
    now.getUTCMonth() + 1,
    now.getUTCDate()
  ).getTime();

  if (parsed.getTime() > today) {
    return null;
  }

  return parsed;
}

/** True when a supplied value is a legitimate canonical birth date. */
export function isValidBirthDate(value, options) {
  return parseBirthDate(value, options) !== null;
}

/**
 * The canonical `YYYY-MM-DD` for a stored value, or `null`.
 *
 * Reading UTC components keeps the exposed calendar date identical to the one
 * that was submitted, and never leaks a full ISO timestamp for this field.
 */
export function formatBirthDate(value) {
  if (value === null || value === undefined || value === '') {
    return null;
  }

  const date = value instanceof Date ? value : new Date(value);

  if (Number.isNaN(date.getTime())) {
    return null;
  }

  const year = String(date.getUTCFullYear()).padStart(4, '0');
  const month = String(date.getUTCMonth() + 1).padStart(2, '0');
  const day = String(date.getUTCDate()).padStart(2, '0');

  return `${year}-${month}-${day}`;
}
