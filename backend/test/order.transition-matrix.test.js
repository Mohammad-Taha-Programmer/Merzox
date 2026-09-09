import assert from 'node:assert/strict';
import test from 'node:test';

import mongoose from 'mongoose';

import { Order } from '../src/models/Order.js';
import {
  ORDER_CANCELLATION_WINDOW_MS,
  addressMutableStatuses,
  allowedOwnerTransitions,
  canAssignCourier,
  canChangeDeliveryAddress,
  canCustomerCancel,
  canReviewOrder,
  canTransitionOwnerOrder,
  customerCancellationRefusal,
  earliestCancellableOrderDate,
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

  // Just placed, so the 24-hour window is wide open and status is the only
  // thing being asserted here. The window has its own test below.
  const justPlaced = { createdAt: new Date() };

  for (const status of orderStatuses) {
    assert.equal(
      canCustomerCancel({ status, ...justPlaced }),
      expected[status].cancel,
      `cancel ${status}`
    );
    assert.equal(
      canChangeDeliveryAddress(status),
      expected[status].address,
      `address ${status}`
    );
    assert.equal(canReviewOrder(status), expected[status].review, `review ${status}`);
  }

  // Address mutation must be a strict subset of cancellation.
  for (const status of addressMutableStatuses) {
    assert.equal(canCustomerCancel({ status, ...justPlaced }), true, status);
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

    assert.equal(
      tracking.canCancel,
      canCustomerCancel({ status, createdAt: undefined }),
      `cancel ${status}`
    );
    assert.equal(
      tracking.canChangeAddress,
      canChangeDeliveryAddress(status),
      `address ${status}`
    );
    assert.equal(tracking.canReview, canReviewOrder(status), `review ${status}`);
  }
});

test('cancellation closes 24 hours after the order was placed', () => {
  // The checkout screen promises a day, so a day is what the rule gives -
  // measured from when the order was created, not from any later moment.
  const now = Date.UTC(2026, 0, 30, 12, 0, 0);
  const at = (msAgo) => ({ status: 'confirmed', createdAt: new Date(now - msAgo) });

  assert.equal(canCustomerCancel(at(0), now), true, 'just placed');
  assert.equal(
    canCustomerCancel(at(ORDER_CANCELLATION_WINDOW_MS - 1000), now),
    true,
    'a second inside the window'
  );
  assert.equal(
    canCustomerCancel(at(ORDER_CANCELLATION_WINDOW_MS), now),
    false,
    'exactly a day old'
  );
  assert.equal(
    canCustomerCancel(at(ORDER_CANCELLATION_WINDOW_MS + 1000), now),
    false,
    'a second past the window'
  );

  // The query bound and the decision have to close at the same instant, or an
  // order can be refused by one and accepted by the other.
  assert.equal(
    earliestCancellableOrderDate(now).getTime(),
    now - ORDER_CANCELLATION_WINDOW_MS
  );
});

test('a refusal says which gate closed', () => {
  // A reader told only "no" concludes the app is broken, so each refusal
  // carries its own reason - and the two reasons are never confused.
  const now = Date.UTC(2026, 0, 30, 12, 0, 0);
  const fresh = new Date(now - 1000);
  const stale = new Date(now - ORDER_CANCELLATION_WINDOW_MS - 1000);

  assert.equal(
    customerCancellationRefusal({ status: 'confirmed', createdAt: fresh }, now),
    null
  );
  assert.equal(
    customerCancellationRefusal(
      { status: 'outForDelivery', createdAt: fresh },
      now
    ),
    'ORDER_ALREADY_DISPATCHED'
  );
  assert.equal(
    customerCancellationRefusal({ status: 'confirmed', createdAt: stale }, now),
    'ORDER_CANCELLATION_WINDOW_CLOSED'
  );

  // Already closed, by either road.
  for (const status of ['delivered', 'cancelled']) {
    assert.equal(
      customerCancellationRefusal({ status, createdAt: fresh }, now),
      'ORDER_NOT_CANCELLABLE',
      status
    );
  }

  // Out for delivery *and* stale still reads as dispatched: that is the fact
  // the reader can act on, and the one they will recognise.
  assert.equal(
    customerCancellationRefusal(
      { status: 'outForDelivery', createdAt: stale },
      now
    ),
    'ORDER_ALREADY_DISPATCHED'
  );
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
