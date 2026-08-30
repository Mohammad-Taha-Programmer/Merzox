import assert from 'node:assert/strict';
import test from 'node:test';

import {
  canTransitionOwnerOrder,
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
