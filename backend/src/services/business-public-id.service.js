import crypto from 'node:crypto';

import { Business } from '../models/Business.js';
import { AppError } from '../utils/AppError.js';

export const FREE_BUSINESS_PUBLIC_ID_MIN = 10000;
export const FREE_BUSINESS_PUBLIC_ID_MAX = 99999;

export const RESERVED_BUSINESS_PUBLIC_IDS = Object.freeze([
  10000,
  20000,
  30000,
  40000,
  50000,
  60000,
  70000,
  80000,
  90000,
  11111,
  22222,
  33333,
  44444,
  55555,
  66666,
  77777,
  88888,
  99999,
  100000
]);

const reservedPublicIdSet = new Set(
  RESERVED_BUSINESS_PUBLIC_IDS.map(String)
);

const reservedFreeRangeIds = RESERVED_BUSINESS_PUBLIC_IDS
  .filter(
    (value) =>
      value >= FREE_BUSINESS_PUBLIC_ID_MIN &&
      value <= FREE_BUSINESS_PUBLIC_ID_MAX
  )
  .sort((left, right) => left - right);

export const FREE_BUSINESS_PUBLIC_ID_COUNT =
  FREE_BUSINESS_PUBLIC_ID_MAX -
  FREE_BUSINESS_PUBLIC_ID_MIN +
  1 -
  reservedFreeRangeIds.length;

const DEFAULT_PUBLIC_ID_ALLOCATION_ATTEMPTS = 128;

export function isReservedBusinessPublicId(value) {
  return reservedPublicIdSet.has(String(value).trim());
}

/**
 * Maps a cryptographically random offset onto the available five-digit
 * namespace. Mapping instead of repeated random draws guarantees that a
 * reserved identifier is never returned and keeps every free ID equally
 * likely.
 */
export function generateBusinessPublicId({
  randomInt = crypto.randomInt
} = {}) {
  const offset = randomInt(
    0,
    FREE_BUSINESS_PUBLIC_ID_COUNT
  );

  if (
    !Number.isSafeInteger(offset) ||
    offset < 0 ||
    offset >= FREE_BUSINESS_PUBLIC_ID_COUNT
  ) {
    throw new TypeError(
      'The random source returned an invalid business ID offset'
    );
  }

  let candidate =
    FREE_BUSINESS_PUBLIC_ID_MIN + offset;

  for (const reservedId of reservedFreeRangeIds) {
    if (candidate >= reservedId) {
      candidate += 1;
    } else {
      break;
    }
  }

  return String(candidate);
}

export function isPublicIdDuplicateKeyError(error) {
  if (error?.code !== 11000) {
    return false;
  }

  if (
    error.keyPattern &&
    Object.prototype.hasOwnProperty.call(
      error.keyPattern,
      'publicId'
    )
  ) {
    return true;
  }

  if (
    error.keyValue &&
    Object.prototype.hasOwnProperty.call(
      error.keyValue,
      'publicId'
    )
  ) {
    return true;
  }

  return /publicId(?:_1)?/i.test(
    String(error.message ?? '')
  );
}

/**
 * Checks availability before creation as required by the business rule.
 * The database unique index remains the final concurrency authority; if
 * another request claims the same ID between exists() and create(), this
 * function detects that publicId duplicate and retries safely.
 */
export async function createBusinessWithUniquePublicId(
  businessValues,
  {
    BusinessModel = Business,
    randomInt = crypto.randomInt,
    maxAttempts = DEFAULT_PUBLIC_ID_ALLOCATION_ATTEMPTS
  } = {}
) {
  if (
    !Number.isSafeInteger(maxAttempts) ||
    maxAttempts < 1
  ) {
    throw new TypeError(
      'maxAttempts must be a positive integer'
    );
  }

  for (
    let attempt = 1;
    attempt <= maxAttempts;
    attempt += 1
  ) {
    const publicId = generateBusinessPublicId({
      randomInt
    });

    const alreadyExists = await BusinessModel.exists({
      publicId
    });

    if (alreadyExists) {
      continue;
    }

    try {
      return await BusinessModel.create({
        ...businessValues,
        publicId
      });
    } catch (error) {
      if (isPublicIdDuplicateKeyError(error)) {
        continue;
      }

      throw error;
    }
  }

  throw new AppError(
    'A unique business identifier could not be allocated',
    503,
    'BUSINESS_PUBLIC_ID_UNAVAILABLE'
  );
}
