import assert from 'node:assert/strict';
import test from 'node:test';

import {
  MANUAL_ORDER_NOTIFY_COOLDOWN_MS,
  manualNotifyRetryAfterMs
} from '../src/controllers/merchant.controller.js';
import { Order } from '../src/models/Order.js';

// `تفاصيل الطلب` puts `إرسال إشعار` beside the status control, for the case
// where the status has not changed but the customer has not noticed it. Every
// press lands in someone's notifications, so the cooldown is the whole point of
// the endpoint being more than a call to the notifier.

test('an order that was never notified by hand may be notified now', () => {
  assert.equal(manualNotifyRetryAfterMs(null), 0);
  assert.equal(manualNotifyRetryAfterMs(undefined), 0);
});

test('an order notified within the cooldown must wait out the remainder', () => {
  const now = new Date('2026-08-31T10:00:00.000Z');
  const tenSecondsAgo = new Date(now.getTime() - 10_000);

  assert.equal(
    manualNotifyRetryAfterMs(tenSecondsAgo, now),
    MANUAL_ORDER_NOTIFY_COOLDOWN_MS - 10_000
  );
});

test('an order notified before the cooldown elapsed may be notified again', () => {
  const now = new Date('2026-08-31T10:00:00.000Z');

  for (const elapsed of [
    MANUAL_ORDER_NOTIFY_COOLDOWN_MS,
    MANUAL_ORDER_NOTIFY_COOLDOWN_MS + 1,
    MANUAL_ORDER_NOTIFY_COOLDOWN_MS * 10
  ]) {
    const at = new Date(now.getTime() - elapsed);
    assert.equal(manualNotifyRetryAfterMs(at, now), 0);
  }
});

test('the stored timestamp is read as a date even when it arrives as text', () => {
  const now = new Date('2026-08-31T10:00:00.000Z');

  assert.equal(
    manualNotifyRetryAfterMs('2026-08-31T09:59:30.000Z', now),
    30_000
  );
});

test('a clock that moved backwards never hands out more than the cooldown', () => {
  const now = new Date('2026-08-31T10:00:00.000Z');
  const future = new Date(now.getTime() + 3_600_000);

  assert.equal(
    manualNotifyRetryAfterMs(future, now),
    MANUAL_ORDER_NOTIFY_COOLDOWN_MS
  );
});

test('an unparseable timestamp is treated as never notified', () => {
  assert.equal(manualNotifyRetryAfterMs('not a date'), 0);
});

test('a new order carries no manual-notify stamp', () => {
  const order = new Order({});

  assert.equal(order.lastManualNotifyAt, null);
});

test('the merchant view of an order exposes when it was last notified', () => {
  const order = new Order({});
  const at = new Date('2026-08-31T10:00:00.000Z');
  order.lastManualNotifyAt = at;

  assert.equal(order.toMerchantJSON().lastManualNotifyAt.getTime(), at.getTime());
});

test('the customer view of an order does not expose it', () => {
  const order = new Order({ business: '64b000000000000000000009' });
  order.lastManualNotifyAt = new Date();

  // When the merchant last pressed a button is the merchant's business, and
  // the customer already got the notification itself.
  assert.equal('lastManualNotifyAt' in order.toClientJSON(), false);
});
