import assert from 'node:assert/strict';
import test from 'node:test';

import mongoose from 'mongoose';

import { Order } from '../src/models/Order.js';
import {
  addressMutableStatuses,
  allowedOwnerTransitions,
  canAssignCourier,
  canChangeDeliveryAddress,
  canCustomerCancel,
  canReviewOrder,
  canTransitionOwnerOrder,
  isTerminalOrderStatus,
  merchantSelectableStatuses,
  orderStatuses,
  statusGroupFor
} from '../src/policies/order-status.policy.js';

/**
 * FIX2-F: every source status is asserted against every destination status,
 * so a transition can only be permitted by appearing in the policy - never by
 * being overlooked.
 */

/** The complete intended matrix, written out rather than derived. */
const EXPECTED_MERCHANT_TRANSITIONS = {
  pending: ['confirmed', 'cancelled'],
  confirmed: ['preparing', 'cancelled'],
  preparing: ['outForDelivery', 'cancelled'],
  outForDelivery: ['delivered'],
  delivered: [],
  cancelled: []
};

function buildOrder(overrides = {}) {
  return new Order({
    user: new mongoose.Types.ObjectId(),
    business: new mongoose.Types.ObjectId(),
    businessName: 'متجر الاختبار',
    items: [
      {
        productId: new mongoose.Types.ObjectId(),
        name: 'منتج',
        unitPrice: 10,
        quantity: 1
      }
    ],
    subtotal: 10,
    deliveryFee: 10,
    total: 20,
    deliveryAddress: 'رام الله ، دوار المنارة',
    ...overrides
  });
}

test('every source/destination pair matches the declared matrix', () => {
  let allowed = 0;
  let refused = 0;

  for (const from of orderStatuses) {
    for (const to of orderStatuses) {
      const shouldAllow = EXPECTED_MERCHANT_TRANSITIONS[from].includes(to);
      assert.equal(
        canTransitionOwnerOrder(from, to),
        shouldAllow,
        `${from} -> ${to} should be ${shouldAllow ? 'allowed' : 'refused'}`
      );
      shouldAllow ? allowed++ : refused++;
    }
  }

  // 6 x 6 pairs, all asserted.
  assert.equal(allowed + refused, 36);
  assert.equal(allowed, 7);
});

test('a status can never transition to itself', () => {
  for (const status of orderStatuses) {
    assert.equal(canTransitionOwnerOrder(status, status), false, status);
  }
});

test('terminal states cannot be reopened', () => {
  for (const terminal of ['delivered', 'cancelled']) {
    assert.equal(isTerminalOrderStatus(terminal), true);
    assert.deepEqual(allowedOwnerTransitions(terminal), []);

    for (const to of orderStatuses) {
      assert.equal(
        canTransitionOwnerOrder(terminal, to),
        false,
        `${terminal} -> ${to} must stay refused`
      );
    }
  }
});

test('the forward path is exactly one route to delivered', () => {
  const path = ['pending', 'confirmed', 'preparing', 'outForDelivery', 'delivered'];

  for (let index = 0; index < path.length - 1; index++) {
    assert.equal(canTransitionOwnerOrder(path[index], path[index + 1]), true);
  }

  // No skipping ahead.
  assert.equal(canTransitionOwnerOrder('pending', 'delivered'), false);
  assert.equal(canTransitionOwnerOrder('pending', 'outForDelivery'), false);
  assert.equal(canTransitionOwnerOrder('confirmed', 'delivered'), false);
  assert.equal(canTransitionOwnerOrder('preparing', 'delivered'), false);
});

test('an unknown status is never a valid source or destination', () => {
  for (const bogus of ['shipped', 'refunded', '', 'PENDING', 'delivered ']) {
    assert.equal(canTransitionOwnerOrder(bogus, 'confirmed'), false, bogus);
    assert.equal(canTransitionOwnerOrder('pending', bogus), false, bogus);
  }
});

test('pending is reachable from nowhere', () => {
  for (const from of orderStatuses) {
    assert.equal(canTransitionOwnerOrder(from, 'pending'), false, from);
  }
  assert.equal(merchantSelectableStatuses.includes('pending'), false);
});

test('statusGroup is defined for every status', () => {
  const expected = {
    pending: 'current',
    confirmed: 'current',
    preparing: 'current',
    outForDelivery: 'current',
    delivered: 'completed',
    cancelled: 'cancelled'
  };

  for (const status of orderStatuses) {
    assert.equal(statusGroupFor(status), expected[status], status);
  }
});

test('customer capabilities are defined for every status', () => {
  const expected = {
    pending: { cancel: true, address: true, review: false },
    confirmed: { cancel: true, address: true, review: false },
    preparing: { cancel: true, address: false, review: false },
    outForDelivery: { cancel: false, address: false, review: false },
    delivered: { cancel: false, address: false, review: true },
    cancelled: { cancel: false, address: false, review: false }
  };

  for (const status of orderStatuses) {
    assert.equal(canCustomerCancel(status), expected[status].cancel, `cancel ${status}`);
    assert.equal(
      canChangeDeliveryAddress(status),
      expected[status].address,
      `address ${status}`
    );
    assert.equal(canReviewOrder(status), expected[status].review, `review ${status}`);
  }

  // Address mutation must be a strict subset of cancellation.
  for (const status of addressMutableStatuses) {
    assert.equal(canCustomerCancel(status), true, status);
  }
});

test('a courier may only be assigned while the order is live', () => {
  const expected = {
    pending: false,
    confirmed: true,
    preparing: true,
    outForDelivery: true,
    delivered: false,
    cancelled: false
  };

  for (const status of orderStatuses) {
    assert.equal(canAssignCourier(status), expected[status], status);
  }
});

test('the model projection agrees with the policy for every status', () => {
  // The tracking screen and the server must never disagree about what the
  // customer is allowed to do.
  for (const status of orderStatuses) {
    const tracking = buildOrder({ status }).trackingJSON();

    assert.equal(tracking.canCancel, canCustomerCancel(status), `cancel ${status}`);
    assert.equal(
      tracking.canChangeAddress,
      canChangeDeliveryAddress(status),
      `address ${status}`
    );
    assert.equal(tracking.canReview, canReviewOrder(status), `review ${status}`);
  }
});

test('a refused transition leaves the stored order untouched', () => {
  // The controller guards the write with `status: order.status`, so a refused
  // transition never reaches the database. This asserts the decision half:
  // nothing about the order is mutated by evaluating the policy.
  const order = buildOrder({ status: 'delivered', statusGroup: 'completed' });

  for (const to of orderStatuses) {
    canTransitionOwnerOrder(order.status, to);
  }

  assert.equal(order.status, 'delivered');
  assert.equal(order.statusGroup, 'completed');
  assert.equal(order.statusHistory.length, 1);
});

test('the merchant selectable list contains only reachable statuses', () => {
  const reachable = new Set(
    orderStatuses.flatMap((from) => allowedOwnerTransitions(from))
  );

  for (const status of merchantSelectableStatuses) {
    assert.equal(reachable.has(status), true, `${status} must be reachable`);
  }
  assert.equal(reachable.size, merchantSelectableStatuses.length);
});
