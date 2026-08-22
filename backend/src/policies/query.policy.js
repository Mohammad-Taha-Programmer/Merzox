import { AppError } from '../utils/AppError.js';

/**
 * The shared query contract for list endpoints.
 *
 * `Number.parseInt` was the problem this replaces: it stops at the first
 * non-digit, so `page=2abc` silently became `2` and `limit=5x` became `5`. A
 * malformed value must be refused, not quietly reinterpreted.
 *
 * Contract:
 *   page  - required-shape positive base-10 integer; absent means 1
 *   limit - required-shape positive base-10 integer; absent means 20;
 *           capped at MAX_LIMIT, which is a documented clamp rather than a
 *           rejection so an over-large page size stays a successful request
 *   enums - matched exactly; anything else is refused
 */

export const DEFAULT_PAGE = 1;
export const DEFAULT_LIMIT = 20;
export const MAX_LIMIT = 50;

/** Only a bare run of digits is a valid integer here - no signs, no decimals. */
const INTEGER_PATTERN = /^\d+$/;

/**
 * Parses one positive-integer query parameter.
 *
 * Rejects `2abc`, `1.5`, `-1`, `0`, `abc`, `1e3`, ` 2 ` with a leading sign,
 * and repeated parameters (which Express surfaces as an array).
 */
export function positiveIntegerParam(
  value,
  { name, fallback, max = null, code }
) {
  if (value === undefined || value === null || value === '') {
    return fallback;
  }

  // A repeated query parameter arrives as an array; there is no single answer.
  if (Array.isArray(value)) {
    throw new AppError(`${name} is invalid`, 400, code);
  }

  const raw = String(value).trim();
  if (!INTEGER_PATTERN.test(raw)) {
    throw new AppError(`${name} is invalid`, 400, code);
  }

  const parsed = Number(raw);
  if (!Number.isSafeInteger(parsed) || parsed < 1) {
    throw new AppError(`${name} is invalid`, 400, code);
  }

  // Clamping the upper bound is deliberate and documented: a caller asking for
  // more than the server will serve gets the maximum, not an error.
  return max === null ? parsed : Math.min(parsed, max);
}

export function paginationParams(query = {}) {
  const page = positiveIntegerParam(query.page, {
    name: 'page',
    fallback: DEFAULT_PAGE,
    code: 'INVALID_PAGE'
  });
  const limit = positiveIntegerParam(query.limit, {
    name: 'limit',
    fallback: DEFAULT_LIMIT,
    max: MAX_LIMIT,
    code: 'INVALID_LIMIT'
  });

  return { page, limit, skip: (page - 1) * limit };
}

/**
 * Matches a query value against an allowlist. An unrecognised value is refused
 * rather than folded into the default, so `filter=banana` can never be served
 * as `all`.
 */
export function enumParam(value, { name, allowed, fallback, code }) {
  if (value === undefined || value === null || value === '') {
    return fallback;
  }

  if (Array.isArray(value)) {
    throw new AppError(`${name} is invalid`, 400, code);
  }

  const raw = String(value).trim();
  if (!allowed.includes(raw)) {
    throw new AppError(
      `${name} must be one of: ${allowed.join(', ')}`,
      400,
      code
    );
  }

  return raw;
}

export const READ_FILTERS = ['all', 'unread'];
export const NOTIFICATION_AUDIENCES = ['customer', 'business'];

export function readFilterParam(value, code) {
  return enumParam(value, {
    name: 'filter',
    allowed: READ_FILTERS,
    fallback: 'all',
    code
  });
}
