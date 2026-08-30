import assert from 'node:assert/strict';
import test from 'node:test';

import {
  DEFAULT_DELIVERY_OPTION,
  DELIVERY_OPTIONS,
  deliveryFeeFor,
  isDeliveryOption,
  totalFor
} from '../src/policies/checkout.policy.js';
import { checkoutFingerprint } from '../src/policies/checkout-intent.policy.js';

// The delivery tiers of `تفاصيل المتجر – 24`.
//
// The artboard offers 10.00 for an estimated window and 30.00 for immediate.
// Both prices live in the policy and nowhere else: the client names a tier,
// never a price.

test('the tiers are the two the checkout screen draws', () => {
  assert.deepEqual(DELIVERY_OPTIONS, { standard: 10, express: 30 });
  assert.equal(DEFAULT_DELIVERY_OPTION, 'standard');
});

test('an order that names no tier is charged what it always was', () => {
  // Every order placed before this choice existed paid the flat 10.
  assert.equal(deliveryFeeFor(35), 10);
  assert.equal(totalFor(35), 45);
});

test('the express tier costs what the policy says', () => {
  assert.equal(deliveryFeeFor(35, 'express'), 30);
  assert.equal(totalFor(35, 'express'), 65);
});

test('nothing payable is charged no delivery, whatever the tier', () => {
  // A fully discounted basket must not be handed a delivery charge alone.
  assert.equal(deliveryFeeFor(0), 0);
  assert.equal(deliveryFeeFor(0, 'express'), 0);
});

test('an unknown tier is refused, not resolved to the cheapest', () => {
  assert.equal(isDeliveryOption('standard'), true);
  assert.equal(isDeliveryOption('express'), true);
  assert.equal(isDeliveryOption('free'), false);

  assert.throws(() => deliveryFeeFor(35, 'free'), {
    code: 'INVALID_DELIVERY_OPTION'
  });
  assert.throws(() => deliveryFeeFor(35, ''), {
    code: 'INVALID_DELIVERY_OPTION'
  });
});

test('the tier price cannot be dictated by its own name', () => {
  // Whatever a caller passes, the fee is looked up rather than read.
  for (const [option, fee] of Object.entries(DELIVERY_OPTIONS)) {
    assert.equal(deliveryFeeFor(1, option), fee);
  }
});

// ---------------------------------------------------------------------------
// Fingerprint compatibility.
// ---------------------------------------------------------------------------

const BASKET = {
  businessId: '64b000000000000000000001',
  items: [{ productId: '64c000000000000000000001', quantity: 2 }],
  deliveryAddress: 'رام الله',
  paymentMethod: 'cash'
};

test('a standard order fingerprints exactly as it did before tiers', () => {
  // The retry of an order placed before this change must still find its own
  // intent, so naming the standard tier may not alter the hash.
  const before = checkoutFingerprint(BASKET);

  assert.equal(checkoutFingerprint({ ...BASKET, deliveryOption: 'standard' }), before);
  assert.equal(checkoutFingerprint({ ...BASKET, deliveryOption: undefined }), before);
  assert.equal(checkoutFingerprint({ ...BASKET, deliveryOption: '' }), before);
});

test('two tiers of the same basket are two different orders', () => {
  // They cost different amounts, so reusing one key across them is a client
  // bug the fingerprint has to catch.
  assert.notEqual(
    checkoutFingerprint({ ...BASKET, deliveryOption: 'express' }),
    checkoutFingerprint({ ...BASKET, deliveryOption: 'standard' })
  );
});
