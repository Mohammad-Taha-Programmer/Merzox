import assert from 'node:assert/strict';
import test from 'node:test';

import {
  ownerOrderFilterFields
} from '../src/controllers/merchant.controller.js';

/// The dashboard's period control.
///
/// The figures above the orders table used to count every order the shop had
/// ever taken, whatever period was asked for, so "this month" and "last week"
/// showed the same sales. The controller now narrows its aggregate with the
/// same reading the orders list uses, and these hold that reading still.

test('a period narrows to the days asked for, end of day included', () => {
  const filter = ownerOrderFilterFields({ from: '2026-09-01', to: '2026-09-30' });

  assert.ok(filter.createdAt, 'a period must produce a createdAt bound');
  assert.equal(filter.createdAt.$gte.toISOString(), '2026-09-01T00:00:00.000Z');

  // A merchant asking "to the 30th" means the whole of the 30th.
  assert.equal(filter.createdAt.$lte.toISOString(), '2026-09-30T23:59:59.999Z');
});

test('an open end is allowed at either side', () => {
  const onlyFrom = ownerOrderFilterFields({ from: '2026-01-01' });
  assert.ok(onlyFrom.createdAt.$gte);
  assert.equal(onlyFrom.createdAt.$lte, undefined);

  const onlyTo = ownerOrderFilterFields({ to: '2026-01-31' });
  assert.equal(onlyTo.createdAt.$gte, undefined);
  assert.ok(onlyTo.createdAt.$lte);
});

test('no period leaves the figures untouched', () => {
  assert.equal(ownerOrderFilterFields({}).createdAt, undefined);
  assert.equal(ownerOrderFilterFields({ from: '', to: '' }).createdAt, undefined);
});

test('a period that is not a calendar day is refused, not guessed at', () => {
  for (const bad of ['01-09-2026', '2026/09/01', 'yesterday', '2026-9-1']) {
    assert.throws(
      () => ownerOrderFilterFields({ from: bad }),
      (error) => error.code === 'INVALID_ORDER_DATE_FROM',
      `${bad} must be refused`
    );
  }

  assert.throws(
    () => ownerOrderFilterFields({ to: ['2026-01-01', '2026-02-01'] }),
    (error) => error.code === 'INVALID_ORDER_DATE_TO'
  );
});
