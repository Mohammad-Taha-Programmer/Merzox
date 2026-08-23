import assert from 'node:assert/strict';
import test from 'node:test';

import { requireCustomerUser } from '../src/middleware/auth.js';
import {
  assertReviewEligible,
  getReviewEligibility,
  reviewEligibilityReasons
} from '../src/services/review-eligibility.service.js';

function normalUser() {
  return {
    _id: 'customer-1',
    userType: 'normal'
  };
}

function fakeOrderModel({ existsResult = null } = {}) {
  const calls = [];

  return {
    calls,
    model: {
      async exists(filter) {
        calls.push(filter);
        return existsResult;
      }
    }
  };
}

test('business review eligibility requires an exact delivered purchase', async () => {
  const fake = fakeOrderModel({ existsResult: { _id: 'order-1' } });

  const result = await getReviewEligibility({
    user: normalUser(),
    businessId: 'business-1',
    orderModel: fake.model
  });

  assert.deepEqual(result, {
    eligible: true,
    reason: null
  });

  assert.deepEqual(fake.calls, [
    {
      user: 'customer-1',
      business: 'business-1',
      status: 'delivered'
    }
  ]);
});

test('product eligibility proves the exact product was in a delivered order', async () => {
  const fake = fakeOrderModel({ existsResult: { _id: 'order-2' } });

  const result = await getReviewEligibility({
    user: normalUser(),
    businessId: 'business-1',
    productId: 'product-7',
    orderModel: fake.model
  });

  assert.equal(result.eligible, true);

  assert.deepEqual(fake.calls, [
    {
      user: 'customer-1',
      business: 'business-1',
      status: 'delivered',
      'items.productId': 'product-7'
    }
  ]);
});

test('pending, cancelled, or absent purchases cannot be synthesized as eligible', async () => {
  const fake = fakeOrderModel({ existsResult: null });

  const result = await getReviewEligibility({
    user: normalUser(),
    businessId: 'business-1',
    orderModel: fake.model
  });

  assert.deepEqual(result, {
    eligible: false,
    reason: reviewEligibilityReasons.deliveredPurchaseRequired
  });

  assert.equal(fake.calls[0].status, 'delivered');
});

test('business accounts are not customer reviewers and do not query orders', async () => {
  const fake = fakeOrderModel({ existsResult: { _id: 'order-1' } });

  const result = await getReviewEligibility({
    user: {
      _id: 'merchant-1',
      userType: 'business'
    },
    businessId: 'business-1',
    orderModel: fake.model
  });

  assert.deepEqual(result, {
    eligible: false,
    reason: reviewEligibilityReasons.customerAccountRequired
  });

  assert.equal(fake.calls.length, 0);
});

test('write-time fence rejects a normal user without delivered proof', async () => {
  const fake = fakeOrderModel({ existsResult: null });

  await assert.rejects(
    () =>
      assertReviewEligible({
        user: normalUser(),
        businessId: 'business-1',
        productId: 'product-1',
        orderModel: fake.model
      }),
    (error) => {
      assert.equal(error.statusCode, 403);
      assert.equal(error.code, 'REVIEW_NOT_ELIGIBLE');
      return true;
    }
  );
});

test('write-time fence rejects a business account with a stable code', async () => {
  const fake = fakeOrderModel();

  await assert.rejects(
    () =>
      assertReviewEligible({
        user: {
          _id: 'merchant-1',
          userType: 'business'
        },
        businessId: 'business-1',
        orderModel: fake.model
      }),
    (error) => {
      assert.equal(error.statusCode, 403);
      assert.equal(error.code, 'CUSTOMER_ACCOUNT_REQUIRED');
      return true;
    }
  );
});

test('requireCustomerUser permits normal customers only', () => {
  let nextCalls = 0;

  requireCustomerUser(
    { user: normalUser() },
    {},
    () => {
      nextCalls += 1;
    }
  );

  assert.equal(nextCalls, 1);

  assert.throws(
    () =>
      requireCustomerUser(
        {
          user: {
            _id: 'merchant-1',
            userType: 'business'
          }
        },
        {},
        () => {}
      ),
    (error) => {
      assert.equal(error.statusCode, 403);
      assert.equal(error.code, 'CUSTOMER_ACCOUNT_REQUIRED');
      return true;
    }
  );
});
