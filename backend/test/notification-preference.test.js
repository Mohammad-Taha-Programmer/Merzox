import assert from 'node:assert/strict';
import test from 'node:test';

import { User } from '../src/models/User.js';
import {
  NOTIFICATION_PREFERENCES,
  notificationPreferenceView,
  parseNotificationPreferencePatch,
  updateNotificationPreference,
  updateProductOffersPreference
} from '../src/services/notification-preference.service.js';

// Two preferences, kept apart on purpose: `productOffers` is the customer's
// marketing switch and `orderUpdates` is the merchant's, which `البروفايل`
// puts at the foot of the merchant menu. One key controlling both would mean a
// shop owner silencing marketing also silenced "you have a new order".

test('the service knows exactly the two preferences that exist', () => {
  assert.deepEqual([...NOTIFICATION_PREFERENCES], [
    'productOffers',
    'orderUpdates'
  ]);
});

test('legacy users without a stored preference resolve to enabled', () => {
  // An absent value is not a refusal — including for a document written
  // before either key existed.
  assert.deepEqual(notificationPreferenceView({}), {
    productOffers: true,
    orderUpdates: true
  });
  assert.deepEqual(
    notificationPreferenceView({ notificationPreferences: {} }),
    { productOffers: true, orderUpdates: true }
  );
});

test('an explicit stored false preference remains false', () => {
  assert.deepEqual(
    notificationPreferenceView({
      notificationPreferences: { productOffers: false }
    }),
    { productOffers: false, orderUpdates: true }
  );
  assert.deepEqual(
    notificationPreferenceView({
      notificationPreferences: { orderUpdates: false }
    }),
    { productOffers: true, orderUpdates: false }
  );
});

test('one preference is silenced without touching the other', () => {
  assert.deepEqual(
    notificationPreferenceView({
      notificationPreferences: { productOffers: false, orderUpdates: true }
    }),
    { productOffers: false, orderUpdates: true }
  );
});

test('the patch reads exactly one known boolean field', () => {
  assert.deepEqual(parseNotificationPreferencePatch({ productOffers: true }), {
    key: 'productOffers',
    value: true
  });
  assert.deepEqual(parseNotificationPreferencePatch({ orderUpdates: false }), {
    key: 'orderUpdates',
    value: false
  });
});

test('the patch refuses anything that is not one known boolean', () => {
  const invalidPayloads = [
    null,
    [],
    {},
    { productOffers: 'true' },
    { productOffers: 1 },
    // Two at once: a partial failure would be ambiguous, and no screen sets
    // both.
    { productOffers: true, orderUpdates: false },
    { productOffers: true, extra: false },
    // An unrecognised key is refused rather than stored and forgotten.
    { marketingEmails: true }
  ];

  for (const payload of invalidPayloads) {
    assert.throws(
      () => parseNotificationPreferencePatch(payload),
      (error) => {
        assert.equal(error.statusCode, 400);
        assert.equal(error.code, 'INVALID_NOTIFICATION_PREFERENCE');
        return true;
      }
    );
  }
});

test('authoritative update persists the requested preference before returning it', async () => {
  const user = {
    notificationPreferences: { productOffers: true, orderUpdates: true },
    saveCalls: 0,
    async save() {
      this.saveCalls += 1;
    }
  };

  const result = await updateNotificationPreference({
    user,
    key: 'orderUpdates',
    value: false
  });

  assert.equal(user.saveCalls, 1);
  assert.equal(user.notificationPreferences.orderUpdates, false);
  // The other one is untouched.
  assert.equal(user.notificationPreferences.productOffers, true);
  assert.deepEqual(result, { productOffers: true, orderUpdates: false });
});

test('authoritative update rejects a non-boolean or an unknown key', async () => {
  const user = {
    notificationPreferences: { productOffers: true },
    async save() {
      throw new Error('save must not run');
    }
  };

  for (const patch of [
    { key: 'productOffers', value: 'false' },
    { key: 'marketingEmails', value: true }
  ]) {
    await assert.rejects(
      () => updateNotificationPreference({ user, ...patch }),
      (error) => {
        assert.equal(error.statusCode, 400);
        assert.equal(error.code, 'INVALID_NOTIFICATION_PREFERENCE');
        return true;
      }
    );
  }
});

test('the pre-orderUpdates entry point still sets what it always set', async () => {
  const user = {
    notificationPreferences: { productOffers: true, orderUpdates: true },
    async save() {}
  };

  const result = await updateProductOffersPreference({
    user,
    productOffers: false
  });

  assert.equal(user.notificationPreferences.productOffers, false);
  assert.equal(user.notificationPreferences.orderUpdates, true);
  assert.deepEqual(result, { productOffers: false, orderUpdates: true });
});

test('new User documents default both preferences to enabled', () => {
  const user = new User({
    name: 'Preference Test',
    passwordHash: 'not-used-by-this-test'
  });

  assert.equal(user.notificationPreferences.productOffers, true);
  assert.equal(user.notificationPreferences.orderUpdates, true);
});
