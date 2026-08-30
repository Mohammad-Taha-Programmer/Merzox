import assert from 'node:assert/strict';
import test from 'node:test';

import {
  canTransitionOwnerOrder,
  ownerOrderFilterFields,
  ownerOrderSearchFilter
} from '../src/controllers/merchant.controller.js';

test('merchant order transitions follow the fulfillment lifecycle', () => {
  assert.equal(canTransitionOwnerOrder('pending', 'confirmed'), true);
  assert.equal(canTransitionOwnerOrder('confirmed', 'preparing'), true);
  assert.equal(canTransitionOwnerOrder('preparing', 'outForDelivery'), true);
  assert.equal(canTransitionOwnerOrder('outForDelivery', 'delivered'), true);
});

test('merchant order transitions reject skips and terminal changes', () => {
  assert.equal(canTransitionOwnerOrder('pending', 'delivered'), false);
  assert.equal(canTransitionOwnerOrder('delivered', 'cancelled'), false);
  assert.equal(canTransitionOwnerOrder('cancelled', 'confirmed'), false);
});

test('owner order search matches the two fields its placeholder names', () => {
  assert.deepEqual(ownerOrderSearchFilter({ q: '222321' }), [
    { publicId: { $regex: '222321', $options: 'i' } },
    { customerName: { $regex: '222321', $options: 'i' } }
  ]);
});

test('owner order search is absent unless the merchant typed something', () => {
  assert.equal(ownerOrderSearchFilter({}), null);
  assert.equal(ownerOrderSearchFilter({ q: '' }), null);
  assert.equal(ownerOrderSearchFilter({ q: '   ' }), null);
  assert.equal(ownerOrderSearchFilter({ q: null }), null);
});

test('owner order search escapes the needle instead of running it', () => {
  const [byId] = ownerOrderSearchFilter({ q: 'a.*b' });
  assert.equal(byId.publicId.$regex, 'a\\.\\*b');
  assert.equal(new RegExp(byId.publicId.$regex).test('a.*b'), true);
  assert.equal(new RegExp(byId.publicId.$regex).test('axxb'), false);
});

test('owner order search refuses a repeated parameter', () => {
  assert.throws(() => ownerOrderSearchFilter({ q: ['a', 'b'] }), {
    code: 'INVALID_ORDER_SEARCH'
  });
});

test('owner order search bounds the needle it forwards', () => {
  const [byId] = ownerOrderSearchFilter({ q: 'x'.repeat(200) });
  assert.equal(byId.publicId.$regex.length, 80);
});

test('the order filter sheet matches its two needles separately', () => {
  assert.deepEqual(ownerOrderFilterFields({ orderNumber: '222321' }), {
    publicId: { $regex: '222321', $options: 'i' }
  });
  assert.deepEqual(ownerOrderFilterFields({ customerName: 'ياسمين' }), {
    customerName: { $regex: 'ياسمين', $options: 'i' }
  });
});

test('the order filter sheet intersects the fields it was given', () => {
  const filter = ownerOrderFilterFields({
    orderNumber: '2223',
    customerName: 'ياسمين',
    from: '2022-02-01',
    to: '2022-02-15'
  });

  assert.equal(filter.publicId.$regex, '2223');
  assert.equal(filter.customerName.$regex, 'ياسمين');
  assert.deepEqual(filter.createdAt.$gte, new Date('2022-02-01T00:00:00.000Z'));
});

test('an empty sheet filters nothing', () => {
  assert.deepEqual(ownerOrderFilterFields({}), {});
  assert.deepEqual(
    ownerOrderFilterFields({ orderNumber: '', customerName: '  ', from: '' }),
    {}
  );
});

test('the closing date bound covers the whole day it names', () => {
  const filter = ownerOrderFilterFields({ to: '2022-02-15' });

  // An order placed at 23:59 on the 15th is inside "to the 15th".
  assert.equal(
    filter.createdAt.$lte >= new Date('2022-02-15T23:59:59.000Z'),
    true
  );
  assert.equal(filter.createdAt.$lte < new Date('2022-02-16T00:00:00.000Z'), true);
});

test('the sheet escapes its needles instead of running them', () => {
  const filter = ownerOrderFilterFields({ customerName: 'a.*b' });
  assert.equal(filter.customerName.$regex, 'a\\.\\*b');
});

test('the sheet refuses a date it cannot read', () => {
  assert.throws(() => ownerOrderFilterFields({ from: '15/2/2022' }), {
    code: 'INVALID_ORDER_DATE_FROM'
  });
  assert.throws(() => ownerOrderFilterFields({ to: '2022-02-31' }), {
    code: 'INVALID_ORDER_DATE_TO'
  });
  assert.throws(() => ownerOrderFilterFields({ from: '2022-13-01' }), {
    code: 'INVALID_ORDER_DATE_FROM'
  });
});

test('the sheet refuses a repeated parameter', () => {
  assert.throws(() => ownerOrderFilterFields({ orderNumber: ['a', 'b'] }), {
    code: 'INVALID_ORDER_NUMBER'
  });
  assert.throws(() => ownerOrderFilterFields({ customerName: ['a', 'b'] }), {
    code: 'INVALID_ORDER_CUSTOMER'
  });
});
