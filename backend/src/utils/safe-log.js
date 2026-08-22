/**
 * Bounded primitives for operational logs.
 *
 * Mongoose puts document values straight into `message` (casts, validation
 * failures, duplicate keys), and `stack` carries file paths. Neither may reach
 * a log line, so every diagnostic field is reduced to a short allowlisted
 * primitive here and nowhere else.
 */

/**
 * Only the error class name, and only when it is a short bare identifier.
 * Anything else - including an attacker-shaped `name` - collapses to a
 * constant.
 */
export function safeErrorName(error) {
  const name = error?.name;
  return typeof name === 'string' && /^[A-Za-z]{1,40}$/.test(name)
    ? name
    : 'UnknownError';
}

/**
 * Database error codes are useful (11000 is a duplicate key) but only when
 * they are primitives. A code carrying an object or a long string is dropped.
 */
export function safeErrorCode(error) {
  const code = error?.code;

  if (typeof code === 'number' && Number.isFinite(code)) return code;
  if (typeof code === 'string' && /^[A-Za-z0-9_]{1,40}$/.test(code)) return code;

  return null;
}

/** Renders a code for a log line, using a fixed token when there is none. */
export function formatErrorCode(error) {
  const code = safeErrorCode(error);
  return code === null ? 'none' : code;
}
