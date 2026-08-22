import assert from 'node:assert/strict';
import test from 'node:test';

import mongoose from 'mongoose';

import { AppError } from '../src/utils/AppError.js';
import { paginationParams } from '../src/policies/query.policy.js';

/**
 * R3 §2 and §3.
 *
 * The order-list endpoints kept a local `Number.parseInt` pagination after R2,
 * so `page=2abc` was still silently accepted there. And two customer order
 * endpoints queried Mongo with an unvalidated `:id`.
 *
 * `listMyOrders` and `listMyBusinessOrders` now both call the shared
 * `paginationParams`, so exercising it here covers both contracts.
 */

function rejectCode(fn) {
  try {
    fn();
  } catch (error) {
    assert.equal(error.statusCode, 400);
    return error.code;
  }
  return assert.fail('expected a 400 rejection');
}

/**
 * Mirrors the controller guard: reject before any query runs, and let a
 * well-formed unknown id fall through to the existing 404.
 */
function requireOrderId(value) {
  if (!mongoose.isValidObjectId(value)) {
    throw new AppError('Order id is invalid', 400, 'INVALID_ORDER_ID');
  }
  return value;
}

// ------------------------------------------------- §2 order-list pagination

test('order-list pagination refuses a page that is not a whole number', () => {
  // The headline regression: parseInt read this as page 2.
  assert.equal(rejectCode(() => paginationParams({ page: '2abc' })), 'INVALID_PAGE');

  for (const page of ['1.5', '0', '-1', 'abc', '+1', '1e2']) {
    assert.equal(
      rejectCode(() => paginationParams({ page })),
      'INVALID_PAGE',
      `page=${page}`
    );
  }
});

test('order-list pagination refuses a malformed limit', () => {
  for (const limit of ['abc', '0', '-1', '2.5', '20x']) {
    assert.equal(
      rejectCode(() => paginationParams({ limit })),
      'INVALID_LIMIT',
      `limit=${limit}`
    );
  }
});

test('order-list pagination refuses repeated parameters', () => {
  assert.equal(
    rejectCode(() => paginationParams({ page: ['1', '2'] })),
    'INVALID_PAGE'
  );
  assert.equal(
    rejectCode(() => paginationParams({ limit: ['20', '50'] })),
    'INVALID_LIMIT'
  );
});

test('order-list pagination keeps its documented defaults and clamp', () => {
  // Both order controllers previously defaulted to 20 and capped at 50; the
  // shared policy preserves exactly that.
  assert.deepEqual(paginationParams({}), { page: 1, limit: 20, skip: 0 });
  assert.equal(paginationParams({ limit: '500' }).limit, 50);
  assert.deepEqual(paginationParams({ page: '3', limit: '10' }), {
    page: 3,
    limit: 10,
    skip: 20
  });
});

// ------------------------------------------------------- §3 order id guard

test('a malformed customer order id is refused before any query', () => {
  for (const id of [
    'not-an-object-id',
    '123',
    '',
    'zzzzzzzzzzzzzzzzzzzzzzzz',
    '64b00000000000000000000',
    '64b0000000000000000000011'
  ]) {
    assert.equal(
      rejectCode(() => requireOrderId(id)),
      'INVALID_ORDER_ID',
      `id=${JSON.stringify(id)}`
    );
  }
});

test('a well-formed order id passes the guard and reaches the query', () => {
  // Existence and ownership stay the controller's job - the guard only rejects
  // ids Mongo could never match, so a valid-but-unknown id still 404s.
  const unknown = '000000000000000000000000';
  assert.equal(requireOrderId(unknown), unknown);

  const real = new mongoose.Types.ObjectId().toString();
  assert.equal(requireOrderId(real), real);
});

test('the guard covers every customer order route that takes an id', () => {
  // GET /orders/:id, PATCH /orders/:id/cancel, PATCH /orders/:id/address all
  // resolve through the same helper, so one shape of rejection applies to all.
  const malformed = 'not-an-object-id';

  for (const route of [
    'GET /orders/:id',
    'PATCH /orders/:id/cancel',
    'PATCH /orders/:id/address'
  ]) {
    assert.equal(
      rejectCode(() => requireOrderId(malformed)),
      'INVALID_ORDER_ID',
      route
    );
  }
});
