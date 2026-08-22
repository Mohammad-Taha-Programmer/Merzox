import assert from 'node:assert/strict';
import test from 'node:test';

import {
  validateBusinessOrderStatus,
  validateBusinessProfilePatch,
  validateConversationOpen,
  validateMessageCreate,
  validateOrderAddressPatch,
  validateOrderCourierPatch,
  validateOrderCreate
} from '../src/middleware/validate.js';

/**
 * The validators are the first authorization-adjacent gate on every new route,
 * so they are exercised directly: `accept` proves a legitimate payload passes,
 * `rejectCode` proves a hostile one is refused with a stable error code rather
 * than reaching a controller.
 */
function accept(validator, body) {
  let called = false;
  validator({ body }, undefined, () => {
    called = true;
  });
  assert.equal(called, true, 'expected next() to be called');
}

function rejectCode(validator, body) {
  try {
    validator({ body }, undefined, () => {
      assert.fail('expected the validator to reject this payload');
    });
  } catch (error) {
    assert.equal(error.statusCode, 400);
    return error.code;
  }
  return assert.fail('expected the validator to throw');
}

const VALID_ID = '64b000000000000000000001';

test('an order item may only carry a product and a quantity', () => {
  accept(validateOrderCreate, {
    businessId: VALID_ID,
    items: [{ productId: VALID_ID, quantity: 2 }],
    deliveryAddress: 'رام الله ، دوار المنارة'
  });

  assert.equal(
    rejectCode(validateOrderCreate, {
      businessId: VALID_ID,
      items: [{ productId: VALID_ID, quantity: 1, unitPrice: 1 }],
      deliveryAddress: 'رام الله'
    }),
    'INVALID_ORDER_ITEM'
  );
});

// FIX2-E: the contract changed from a generic field error to a specific one.
// A client needs to distinguish "this product has no variants yet" from
// "your item was malformed", so the code is asserted, not just the status.
test('a supplied product variant is refused with a specific code', () => {
  for (const key of ['variant', 'degree', 'option']) {
    for (const value of ['01', 'red', 'XL', ' 02 ']) {
      assert.equal(
        rejectCode(validateOrderCreate, {
          businessId: VALID_ID,
          items: [{ productId: VALID_ID, quantity: 1, [key]: value }],
          deliveryAddress: 'رام الله'
        }),
        'UNSUPPORTED_PRODUCT_VARIANT',
        `${key}=${JSON.stringify(value)} must be refused`
      );
    }
  }
});

test('an absent or empty variant is accepted', () => {
  // No variant at all.
  accept(validateOrderCreate, {
    businessId: VALID_ID,
    items: [{ productId: VALID_ID, quantity: 1 }],
    deliveryAddress: 'رام الله ، دوار المنارة'
  });

  // An older client that still sends the key, carrying nothing.
  for (const value of ['', '   ', null, undefined]) {
    accept(validateOrderCreate, {
      businessId: VALID_ID,
      items: [{ productId: VALID_ID, quantity: 1, variant: value }],
      deliveryAddress: 'رام الله ، دوار المنارة'
    });
  }
});

test('an order rejects unsupported top-level fields and bad ids', () => {
  // A client must not be able to name the order owner or its totals.
  assert.equal(
    rejectCode(validateOrderCreate, {
      businessId: VALID_ID,
      items: [{ productId: VALID_ID, quantity: 1 }],
      deliveryAddress: 'رام الله',
      user: VALID_ID
    }),
    'INVALID_ORDER_FIELDS'
  );
  assert.equal(
    rejectCode(validateOrderCreate, {
      businessId: VALID_ID,
      items: [{ productId: VALID_ID, quantity: 1 }],
      deliveryAddress: 'رام الله',
      total: 0
    }),
    'INVALID_ORDER_FIELDS'
  );
  assert.equal(
    rejectCode(validateOrderCreate, {
      businessId: 'local-new-0',
      items: [{ productId: VALID_ID, quantity: 1 }],
      deliveryAddress: 'رام الله'
    }),
    'INVALID_BUSINESS_ID'
  );
  assert.equal(
    rejectCode(validateOrderCreate, {
      businessId: VALID_ID,
      items: [{ productId: 'local-product-1', quantity: 1 }],
      deliveryAddress: 'رام الله'
    }),
    'INVALID_PRODUCT_ID'
  );
});

test('order quantities are bounded integers', () => {
  for (const quantity of [0, -1, 101, 1.5, '2', null]) {
    assert.equal(
      rejectCode(validateOrderCreate, {
        businessId: VALID_ID,
        items: [{ productId: VALID_ID, quantity }],
        deliveryAddress: 'رام الله'
      }),
      'INVALID_QUANTITY',
      `quantity ${quantity} should be refused`
    );
  }
});

test('an empty or oversized message body is refused', () => {
  accept(validateMessageCreate, { body: 'متى المتجر بيفتح؟' });

  assert.equal(rejectCode(validateMessageCreate, { body: '' }), 'INVALID_MESSAGE_BODY');
  assert.equal(rejectCode(validateMessageCreate, { body: '   ' }), 'INVALID_MESSAGE_BODY');
  assert.equal(
    rejectCode(validateMessageCreate, { body: 'x'.repeat(2001) }),
    'INVALID_MESSAGE_BODY'
  );
});

test('a message may not carry its own sender or timestamp', () => {
  // Sender identity and time are server-derived; offering them is refused
  // outright rather than silently ignored.
  for (const field of ['senderType', 'senderName', 'createdAt', 'user']) {
    assert.equal(
      rejectCode(validateMessageCreate, { body: 'مرحبا', [field]: 'x' }),
      'INVALID_MESSAGE_FIELDS',
      `${field} should be refused`
    );
  }
});

test('opening a conversation only accepts a business id', () => {
  accept(validateConversationOpen, { businessId: VALID_ID });

  assert.equal(
    rejectCode(validateConversationOpen, { businessId: VALID_ID, user: VALID_ID }),
    'INVALID_CONVERSATION_FIELDS'
  );
  assert.equal(
    rejectCode(validateConversationOpen, { businessId: '' }),
    'INVALID_BUSINESS_ID'
  );
});

test('a delivery address change is bounded and exclusive', () => {
  accept(validateOrderAddressPatch, { deliveryAddress: 'رام الله ، دوار المنارة' });

  assert.equal(
    rejectCode(validateOrderAddressPatch, { deliveryAddress: 'ر' }),
    'INVALID_ORDER_ADDRESS'
  );
  assert.equal(
    rejectCode(validateOrderAddressPatch, { deliveryAddress: 'x'.repeat(251) }),
    'INVALID_ORDER_ADDRESS'
  );
  // Changing the address must not become a way to change the status.
  assert.equal(
    rejectCode(validateOrderAddressPatch, {
      deliveryAddress: 'رام الله ، دوار المنارة',
      status: 'delivered'
    }),
    'INVALID_ORDER_ADDRESS_FIELDS'
  );
});

test('courier details are validated and cannot carry extra fields', () => {
  accept(validateOrderCourierPatch, { name: 'Hamode Hussen', phone: '0592029316' });
  accept(validateOrderCourierPatch, { name: 'Hamode Hussen' });

  assert.equal(rejectCode(validateOrderCourierPatch, { name: 'H' }), 'INVALID_ORDER_COURIER_NAME');
  assert.equal(
    rejectCode(validateOrderCourierPatch, { name: 'Hamode', phone: 'not-a-number' }),
    'INVALID_ORDER_COURIER_PHONE'
  );
  assert.equal(
    rejectCode(validateOrderCourierPatch, { name: 'Hamode', status: 'delivered' }),
    'INVALID_ORDER_COURIER_FIELDS'
  );
});

test('a merchant may only move an order to a real status', () => {
  accept(validateBusinessOrderStatus, { status: 'preparing' });

  assert.equal(
    rejectCode(validateBusinessOrderStatus, { status: 'shipped' }),
    'INVALID_ORDER_STATUS'
  );
  // `pending` is the arrival state, never a transition target.
  assert.equal(
    rejectCode(validateBusinessOrderStatus, { status: 'pending' }),
    'INVALID_ORDER_STATUS'
  );
  assert.equal(
    rejectCode(validateBusinessOrderStatus, { status: 'delivered', business: VALID_ID }),
    'INVALID_ORDER_STATUS_FIELDS'
  );
});

test('store settings are allowlisted and validated', () => {
  accept(validateBusinessProfilePatch, {
    logoUrl: 'https://example.test/logo.png',
    socialLinks: { instagram: 'store', whatsapp: '+972590000001' }
  });
  accept(validateBusinessProfilePatch, { logoUrl: '' });

  // Ownership and rating fields must never be assignable through settings.
  for (const field of ['owner', 'ratingAverage', 'publicId', 'isActive']) {
    assert.equal(
      rejectCode(validateBusinessProfilePatch, { [field]: 'x' }),
      'INVALID_BUSINESS_PROFILE_FIELDS',
      `${field} should be refused`
    );
  }

  assert.equal(
    rejectCode(validateBusinessProfilePatch, { logoUrl: 'javascript:alert(1)' }),
    'INVALID_BUSINESS_LOGO_URL'
  );
  assert.equal(
    rejectCode(validateBusinessProfilePatch, { socialLinks: { whatsapp: 'not-a-number' } }),
    'INVALID_BUSINESS_SOCIAL_NUMBER'
  );
  assert.equal(
    rejectCode(validateBusinessProfilePatch, { socialLinks: { tiktok: 'x' } }),
    'INVALID_BUSINESS_SOCIAL_LINKS'
  );
  assert.equal(
    rejectCode(validateBusinessProfilePatch, { socialLinks: 'x' }),
    'INVALID_BUSINESS_SOCIAL_LINKS'
  );
});
