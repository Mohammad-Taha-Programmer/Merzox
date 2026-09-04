import assert from 'node:assert/strict';
import test from 'node:test';

import {
  validateBusinessOrderStatus,
  validateBusinessProfilePatch,
  validateConversationOpen,
  validateMessageCreate,
  validateOrderAddressPatch,
  validateOrderCourierPatch,
  validateOrderCreate,
  validateProfilePatch
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

/**
 * The payload the Flutter client actually sends.
 *
 * `ApiService.createOrder` has always included `deliveryOption`, and the
 * allowlist did not. Every order in the application was refused at the door
 * with `INVALID_ORDER_FIELDS` - from the basket and from "buy now" alike -
 * while the handler a few lines later read that very field to price the
 * delivery. Nothing caught it because no test sent what the client sends.
 */
test('the order payload the client sends is accepted whole', () => {
  accept(validateOrderCreate, {
    businessId: VALID_ID,
    items: [{ productId: VALID_ID, quantity: 1 }],
    deliveryAddress: 'رام الله ، دوار المنارة',
    paymentMethod: 'cash',
    deliveryOption: 'standard',
    clientOrderId: 'buy-1725000000000000-64b000000000000000000001'
  });
});

test('both delivery tiers pass the gate', () => {
  for (const deliveryOption of ['standard', 'express']) {
    accept(validateOrderCreate, {
      businessId: VALID_ID,
      items: [{ productId: VALID_ID, quantity: 1 }],
      deliveryAddress: 'رام الله ، دوار المنارة',
      deliveryOption
    });
  }
});

test('a field nobody declared is still refused', () => {
  assert.equal(
    rejectCode(validateOrderCreate, {
      businessId: VALID_ID,
      items: [{ productId: VALID_ID, quantity: 1 }],
      deliveryAddress: 'رام الله ، دوار المنارة',
      surpriseField: 'anything'
    }),
    'INVALID_ORDER_FIELDS'
  );
});

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

test('a profile patch accepts an optional canonical birth date', () => {
  accept(validateProfilePatch, { birthDate: '1994-11-07' });
  // A real leap day is a legitimate birthday and must not be refused.
  accept(validateProfilePatch, { birthDate: '2000-02-29' });
  // Optional means omittable, and explicitly clearable.
  accept(validateProfilePatch, { name: 'ليان' });
  accept(validateProfilePatch, { birthDate: null });
});

test('a profile birth date must be a real, past calendar date', () => {
  // February 29th only exists in a leap year, and no month has a 30th of
  // February. `new Date()` would silently normalize both into March.
  for (const value of ['2025-02-29', '2026-02-30', '2000-13-01', '2000-00-01']) {
    assert.equal(
      rejectCode(validateProfilePatch, { birthDate: value }),
      'INVALID_BIRTH_DATE',
      `${value} should be refused`
    );
  }
});

test('a profile birth date is refused when it is not canonical', () => {
  for (const value of [
    '01-02-2000',
    'not-a-date',
    '2000-1-1',
    '2000/01/01',
    ' 2000-01-01 ',
    '2000-01-01T00:00:00.000Z',
    20000101,
    true,
    {},
    []
  ]) {
    assert.equal(
      rejectCode(validateProfilePatch, { birthDate: value }),
      'INVALID_BIRTH_DATE',
      `${JSON.stringify(value)} should be refused`
    );
  }
});

test('the validator accepts every year the selector offers', () => {
  // The year list runs down to 1, so the validator may not stop at some
  // invented age limit and may not read 0001 as 1901.
  for (const value of ['0001-01-01', '0004-02-29', '0099-12-31', '0100-01-01']) {
    accept(validateProfilePatch, { birthDate: value });
  }

  // Year 0000 is not a Gregorian birth year, and year 1 was not a leap year.
  for (const value of ['0000-01-01', '0000-12-31', '0001-02-29']) {
    assert.equal(
      rejectCode(validateProfilePatch, { birthDate: value }),
      'INVALID_BIRTH_DATE',
      `${value} should be refused`
    );
  }
});

test('a profile birth date may not be in the future', () => {
  const tomorrow = new Date(Date.now() + 24 * 60 * 60 * 1000);
  const nextCentury = new Date(Date.UTC(tomorrow.getUTCFullYear() + 100, 0, 1));

  for (const value of [tomorrow, nextCentury]) {
    assert.equal(
      rejectCode(validateProfilePatch, {
        birthDate: value.toISOString().slice(0, 10)
      }),
      'INVALID_BIRTH_DATE',
      `${value.toISOString()} should be refused`
    );
  }

  // Today itself is a legitimate, if unusual, date of birth.
  accept(validateProfilePatch, {
    birthDate: new Date().toISOString().slice(0, 10)
  });
});

test('a profile patch still refuses fields it does not own', () => {
  for (const field of ['birthdate', 'birth_date', 'dob', 'nameChangedAt']) {
    assert.equal(
      rejectCode(validateProfilePatch, { [field]: '2000-01-01' }),
      'INVALID_PROFILE_FIELDS',
      `${field} should be refused`
    );
  }
});
