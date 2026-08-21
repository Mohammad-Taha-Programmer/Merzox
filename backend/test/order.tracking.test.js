import assert from 'node:assert/strict';
import test from 'node:test';

import mongoose from 'mongoose';

import { Notification } from '../src/models/Notification.js';
import { Order } from '../src/models/Order.js';

function buildOrder(overrides = {}) {
  return new Order({
    user: new mongoose.Types.ObjectId(),
    business: new mongoose.Types.ObjectId(),
    businessName: 'متجر الياسمين',
    items: [
      {
        productId: new mongoose.Types.ObjectId(),
        name: 'أساس فت مي',
        unitPrice: 35,
        quantity: 1
      }
    ],
    subtotal: 35,
    deliveryFee: 10,
    total: 45,
    deliveryAddress: 'أريحا ، النبي موسى',
    ...overrides
  });
}

test('a new order starts on the first tracking step', () => {
  const order = buildOrder();

  assert.equal(order.validateSync(), undefined);

  const tracking = order.trackingJSON();
  assert.equal(tracking.currentStep, 'placed');
  assert.equal(tracking.currentIndex, 0);
  assert.equal(tracking.steps.length, 4);
  assert.deepEqual(
    tracking.steps.map((step) => step.isReached),
    [true, false, false, false]
  );
  assert.equal(tracking.canCancel, true);
  assert.equal(tracking.canChangeAddress, true);
  assert.equal(tracking.canReview, false);
});

test('tracking advances with the status history and keeps the first timestamp per step', () => {
  const placedAt = new Date('2026-02-15T14:40:00.000Z');
  const confirmedAt = new Date('2026-02-15T15:00:00.000Z');
  const preparingAt = new Date('2026-02-16T09:00:00.000Z');
  const order = buildOrder({
    status: 'preparing',
    statusHistory: [
      { status: 'pending', changedAt: placedAt },
      { status: 'confirmed', changedAt: confirmedAt },
      { status: 'preparing', changedAt: preparingAt }
    ]
  });

  const tracking = order.trackingJSON();
  assert.equal(tracking.currentStep, 'preparing');
  assert.equal(tracking.currentIndex, 1);
  // `pending` and `confirmed` share the first step; the earlier stamp wins.
  assert.equal(tracking.steps[0].reachedAt.toISOString(), placedAt.toISOString());
  assert.equal(tracking.steps[1].reachedAt.toISOString(), preparingAt.toISOString());
  assert.equal(tracking.steps[2].reachedAt, null);
  assert.equal(tracking.canChangeAddress, false);
  assert.equal(tracking.canCancel, true);
});

test('a delivered order unlocks reviewing and locks cancellation', () => {
  const order = buildOrder({ status: 'delivered', statusGroup: 'completed' });
  const tracking = order.trackingJSON();

  assert.equal(tracking.currentIndex, 3);
  assert.equal(tracking.steps.every((step) => step.isReached), true);
  assert.equal(tracking.canReview, true);
  assert.equal(tracking.canCancel, false);
});

test('a cancelled order reports no active step', () => {
  const order = buildOrder({ status: 'cancelled', statusGroup: 'cancelled' });
  const tracking = order.trackingJSON();

  assert.equal(tracking.isCancelled, true);
  assert.equal(tracking.currentStep, '');
  assert.equal(tracking.currentIndex, -1);
  assert.equal(tracking.steps.some((step) => step.isReached), false);
  assert.equal(tracking.canCancel, false);
  assert.equal(tracking.canReview, false);
});

test('an assigned courier reaches both client payloads', () => {
  const assignedAt = new Date('2026-02-18T12:00:00.000Z');
  const order = buildOrder({
    status: 'outForDelivery',
    courier: { name: 'Hamode Hussen', phone: '0592029316', assignedAt }
  });

  assert.equal(order.validateSync(), undefined);
  assert.equal(order.toClientJSON().courier.name, 'Hamode Hussen');
  assert.equal(order.toMerchantJSON().courier.phone, '0592029316');
  assert.equal(order.toClientJSON().tracking.courier.name, 'Hamode Hussen');
});

test('a notification hides its read state behind a boolean', () => {
  const notification = new Notification({
    user: new mongoose.Types.ObjectId(),
    audience: 'business',
    type: 'orderPlaced',
    title: 'طلب جديد',
    body: 'يوجد لديك طلب جديد رقم MX-TEST',
    data: { publicId: 'MX-TEST' }
  });

  assert.equal(notification.validateSync(), undefined);
  assert.equal(notification.toClientJSON().isRead, false);

  notification.readAt = new Date();
  assert.equal(notification.toClientJSON().isRead, true);
});

test('a notification rejects an unknown type', () => {
  const notification = new Notification({
    user: new mongoose.Types.ObjectId(),
    audience: 'customer',
    type: 'somethingElse'
  });

  assert.notEqual(notification.validateSync(), undefined);
});
