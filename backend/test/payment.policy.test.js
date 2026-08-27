import assert from 'node:assert/strict';
import test from 'node:test';

import { validateOrderCreate } from '../src/middleware/validate.js';
import {
  isKnownPaymentMethod,
  isOperationalPaymentMethod,
  PAYMENT_ERRORS,
  operationalPaymentMethods,
  paymentMethods
} from '../src/policies/payment.policy.js';

const BUSINESS_ID = '64b000000000000000000001';
const PRODUCT_ID = '64c000000000000000000001';

function validBody(overrides = {}) {
  return {
    businessId: BUSINESS_ID,
    items: [
      {
        productId: PRODUCT_ID,
        quantity: 1
      }
    ],
    deliveryAddress: 'Test address',
    clientOrderId: 'payment-test-0001',
    ...overrides
  };
}

function validate(body) {
  let nextCalls = 0;

  validateOrderCreate(
    { body },
    null,
    () => {
      nextCalls += 1;
    }
  );

  return nextCalls;
}

function assertAppError({
  body,
  statusCode,
  code
}) {
  assert.throws(
    () => validate(body),
    (error) => {
      assert.equal(error.statusCode, statusCode);
      assert.equal(error.code, code);
      assert.equal(error.isOperational, true);
      return true;
    }
  );
}

test('payment vocabulary remains the four historical API methods', () => {
  assert.deepEqual(
    [...paymentMethods],
    [
      'cash',
      'card',
      'bankTransfer',
      'assisted'
    ]
  );

  assert.equal(
    Object.isFrozen(paymentMethods),
    true
  );
});

test('cash is the only operational payment method in GAP-020A', () => {
  assert.deepEqual(
    [...operationalPaymentMethods],
    ['cash']
  );

  assert.equal(
    Object.isFrozen(operationalPaymentMethods),
    true
  );
});

test('known and operational payment capability are different truths', () => {
  assert.equal(isKnownPaymentMethod('cash'), true);
  assert.equal(isOperationalPaymentMethod('cash'), true);

  for (const method of [
    'card',
    'bankTransfer',
    'assisted'
  ]) {
    assert.equal(
      isKnownPaymentMethod(method),
      true,
      `${method} must remain recognized`
    );

    assert.equal(
      isOperationalPaymentMethod(method),
      false,
      `${method} must remain unavailable`
    );
  }
});

test('malformed or unknown payment values are not recognized', () => {
  for (const value of [
    '',
    ' cash ',
    'crypto',
    'CARD',
    123,
    {},
    []
  ]) {
    assert.equal(
      isKnownPaymentMethod(value),
      false
    );

    assert.equal(
      isOperationalPaymentMethod(value),
      false
    );
  }
});

test('order validation keeps omitted and null payment methods on cash default semantics', () => {
  assert.equal(
    validate(validBody()),
    1
  );

  assert.equal(
    validate(
      validBody({
        paymentMethod: null
      })
    ),
    1
  );
});

test('order validation accepts explicit cash', () => {
  assert.equal(
    validate(
      validBody({
        paymentMethod: 'cash'
      })
    ),
    1
  );
});

test('known but unavailable methods fail closed with a distinct bounded code', () => {
  assert.equal(
    PAYMENT_ERRORS.unavailable,
    'PAYMENT_METHOD_UNAVAILABLE'
  );

  for (const paymentMethod of [
    'card',
    'bankTransfer',
    'assisted'
  ]) {
    assertAppError({
      body: validBody({
        paymentMethod
      }),
      statusCode: 409,
      code: PAYMENT_ERRORS.unavailable
    });
  }
});

test('unknown payment methods retain INVALID_PAYMENT_METHOD semantics', () => {
  for (const paymentMethod of [
    '',
    'crypto',
    'CARD',
    ' cash '
  ]) {
    assertAppError({
      body: validBody({
        paymentMethod
      }),
      statusCode: 400,
      code: 'INVALID_PAYMENT_METHOD'
    });
  }
});
