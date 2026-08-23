import { AppError } from '../utils/AppError.js';

/**
 * Shared strict query parsing primitives.
 *
 * Defaults preserve the existing contracts of the endpoints that already use
 * this policy. Endpoints that require an exact public syntax can opt out of
 * blank/default and surrounding-whitespace coercion explicitly.
 */

export const DEFAULT_PAGE = 1;
export const DEFAULT_LIMIT = 20;
export const MAX_LIMIT = 50;

const INTEGER_PATTERN = /^\d+$/;
const DECIMAL_PATTERN = /^-?\d+(?:\.\d+)?$/;

function invalidParam(name, code) {
  throw new AppError(`${name} is invalid`, 400, code);
}

/**
 * Parses one positive base-10 integer query parameter.
 *
 * Partial numbers, decimal/exponent notation, signs, unsafe integers and
 * repeated query parameters are rejected.
 */
export function positiveIntegerParam(
  value,
  {
    name,
    fallback,
    max = null,
    code,
    allowBlankAsFallback = true,
    allowSurroundingWhitespace = true
  }
) {
  if (value === undefined || value === null) {
    return fallback;
  }

  if (value === '') {
    if (allowBlankAsFallback) {
      return fallback;
    }
    invalidParam(name, code);
  }

  if (Array.isArray(value)) {
    invalidParam(name, code);
  }

  const text = String(value);
  const raw = allowSurroundingWhitespace ? text.trim() : text;

  if (!INTEGER_PATTERN.test(raw)) {
    invalidParam(name, code);
  }

  const parsed = Number(raw);
  if (!Number.isSafeInteger(parsed) || parsed < 1) {
    invalidParam(name, code);
  }

  return max === null ? parsed : Math.min(parsed, max);
}

/**
 * Parses a plain finite decimal number.
 *
 * The grammar deliberately rejects exponent notation, a leading plus sign,
 * surrounding whitespace, partial numbers and repeated parameters.
 */
export function decimalParam(value, { name, min, max, code }) {
  if (
    value === undefined ||
    value === null ||
    value === '' ||
    Array.isArray(value)
  ) {
    invalidParam(name, code);
  }

  const raw = String(value);

  if (!DECIMAL_PATTERN.test(raw)) {
    invalidParam(name, code);
  }

  const parsed = Number(raw);

  if (
    !Number.isFinite(parsed) ||
    parsed < min ||
    parsed > max
  ) {
    invalidParam(name, code);
  }

  return parsed;
}

export function paginationParams(
  query = {},
  {
    pageFallback = DEFAULT_PAGE,
    limitFallback = DEFAULT_LIMIT,
    maxLimit = MAX_LIMIT,
    allowBlankAsFallback = true,
    allowSurroundingWhitespace = true
  } = {}
) {
  const page = positiveIntegerParam(query.page, {
    name: 'page',
    fallback: pageFallback,
    code: 'INVALID_PAGE',
    allowBlankAsFallback,
    allowSurroundingWhitespace
  });

  const limit = positiveIntegerParam(query.limit, {
    name: 'limit',
    fallback: limitFallback,
    max: maxLimit,
    code: 'INVALID_LIMIT',
    allowBlankAsFallback,
    allowSurroundingWhitespace
  });

  return { page, limit, skip: (page - 1) * limit };
}

/**
 * Matches a query value against an exact allowlist.
 */
export function enumParam(
  value,
  {
    name,
    allowed,
    fallback,
    code,
    allowBlankAsFallback = true,
    allowSurroundingWhitespace = true
  }
) {
  if (value === undefined || value === null) {
    return fallback;
  }

  if (value === '') {
    if (allowBlankAsFallback) {
      return fallback;
    }
    invalidParam(name, code);
  }

  if (Array.isArray(value)) {
    invalidParam(name, code);
  }

  const text = String(value);
  const raw = allowSurroundingWhitespace ? text.trim() : text;

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
