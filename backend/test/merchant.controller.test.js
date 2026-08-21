import assert from 'node:assert/strict';
import test from 'node:test';

import { canTransitionOwnerOrder } from '../src/controllers/merchant.controller.js';

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
