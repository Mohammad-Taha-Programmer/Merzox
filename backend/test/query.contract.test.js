import assert from 'node:assert/strict';
import test from 'node:test';

import {
  DEFAULT_LIMIT,
  DEFAULT_PAGE,
  MAX_LIMIT,
  NOTIFICATION_AUDIENCES,
  enumParam,
  paginationParams,
  positiveIntegerParam,
  readFilterParam
} from '../src/policies/query.policy.js';

/**
 * R2 §3.
 *
 * `Number.parseInt` stops at the first non-digit, so `page=2abc` used to become
 * page 2 and `filter=banana` used to be served as `all`. A malformed value must
 * now be refused, never reinterpreted.
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

test('absent pagination falls back to the documented defaults', () => {
  assert.deepEqual(paginationParams({}), {
    page: DEFAULT_PAGE,
    limit: DEFAULT_LIMIT,
    skip: 0
  });
  assert.deepEqual(paginationParams({ page: '', limit: '' }), {
    page: 1,
    limit: 20,
    skip: 0
  });
});

test('well-formed pagination is accepted and skip is derived', () => {
  assert.deepEqual(paginationParams({ page: '3', limit: '10' }), {
    page: 3,
    limit: 10,
    skip: 20
  });
  assert.deepEqual(paginationParams({ page: 2, limit: 5 }), {
    page: 2,
    limit: 5,
    skip: 5
  });
});

test('a page that is not a whole positive number is refused', () => {
  // The headline case: parseInt would have read this as 2.
  assert.equal(rejectCode(() => paginationParams({ page: '2abc' })), 'INVALID_PAGE');

  for (const page of [
    '1.5',
    '0',
    '-1',
    'abc',
    '1e3',
    '+2',
    ' 2x',
    '0x10',
    'Infinity',
    'NaN',
    '9007199254740993'
  ]) {
    assert.equal(
      rejectCode(() => paginationParams({ page })),
      'INVALID_PAGE',
      `page=${page}`
    );
  }
});

test('a limit that is not a whole positive number is refused', () => {
  for (const limit of ['abc', '0', '-1', '2.5', '5x', '+5']) {
    assert.equal(
      rejectCode(() => paginationParams({ limit })),
      'INVALID_LIMIT',
      `limit=${limit}`
    );
  }
});

test('an over-large limit is clamped, not refused', () => {
  // Documented normalization: asking for more than the server serves yields
  // the maximum rather than an error.
  assert.equal(paginationParams({ limit: '500' }).limit, MAX_LIMIT);
  assert.equal(paginationParams({ limit: String(MAX_LIMIT) }).limit, MAX_LIMIT);
  assert.equal(paginationParams({ limit: String(MAX_LIMIT - 1) }).limit, MAX_LIMIT - 1);
});

test('a repeated query parameter is refused rather than guessed', () => {
  assert.equal(
    rejectCode(() => paginationParams({ page: ['1', '2'] })),
    'INVALID_PAGE'
  );
  assert.equal(
    rejectCode(() => paginationParams({ limit: ['5', '10'] })),
    'INVALID_LIMIT'
  );
});

test('positiveIntegerParam honours its own bounds', () => {
  assert.equal(
    positiveIntegerParam(undefined, { name: 'n', fallback: 7, code: 'INVALID_N' }),
    7
  );
  assert.equal(
    positiveIntegerParam('4', { name: 'n', fallback: 1, max: 3, code: 'INVALID_N' }),
    3
  );
  assert.equal(
    rejectCode(() =>
      positiveIntegerParam('x', { name: 'n', fallback: 1, code: 'INVALID_N' })
    ),
    'INVALID_N'
  );
});

test('a read filter accepts only all or unread', () => {
  assert.equal(readFilterParam(undefined, 'INVALID_FILTER'), 'all');
  assert.equal(readFilterParam('', 'INVALID_FILTER'), 'all');
  assert.equal(readFilterParam('all', 'INVALID_FILTER'), 'all');
  assert.equal(readFilterParam('unread', 'INVALID_FILTER'), 'unread');

  // Previously every unrecognised value silently meant `all`.
  // Note: whitespace is trimmed by design (asserted below), so ' unread ' is
  // deliberately absent here - only genuinely different values are refused.
  for (const filter of ['banana', 'read', 'ALL', 'Unread', '1', 'true']) {
    const code = rejectCode(() => readFilterParam(filter, 'INVALID_FILTER'));
    assert.equal(code, 'INVALID_FILTER', `filter=${filter}`);
  }
});

test('a filter that only differs by whitespace is still accepted', () => {
  // Trimming is intentional; case folding is not.
  assert.equal(readFilterParam(' unread ', 'INVALID_FILTER'), 'unread');
});

test('the notification audience accepts only customer or business', () => {
  const audience = (value) =>
    enumParam(value, {
      name: 'audience',
      allowed: NOTIFICATION_AUDIENCES,
      fallback: 'customer',
      code: 'INVALID_NOTIFICATION_AUDIENCE'
    });

  assert.equal(audience(undefined), 'customer');
  assert.equal(audience('customer'), 'customer');
  assert.equal(audience('business'), 'business');

  for (const value of ['banana', 'admin', 'Business', 'BUSINESS', '1']) {
    assert.equal(
      rejectCode(() => audience(value)),
      'INVALID_NOTIFICATION_AUDIENCE',
      `audience=${value}`
    );
  }
});

test('a rejected enum names the allowed values without echoing the input', () => {
  try {
    readFilterParam('banana', 'INVALID_FILTER');
    assert.fail('expected a rejection');
  } catch (error) {
    assert.match(error.message, /all, unread/);
    assert.equal(error.message.includes('banana'), false);
  }
});
