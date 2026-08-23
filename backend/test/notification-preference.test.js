import assert from 'node:assert/strict';
import test from 'node:test';

import { User } from '../src/models/User.js';
import {
  notificationPreferenceView,
  parseNotificationPreferencePatch,
  updateProductOffersPreference
} from '../src/services/notification-preference.service.js';

test('legacy users without a stored preference resolve to enabled', () => {
  assert.deepEqual(notificationPreferenceView({}), {
    productOffers: true
  });
});

test('an explicit stored false preference remains false', () => {
  assert.deepEqual(
    notificationPreferenceView({
      notificationPreferences: { productOffers: false }
    }),
    { productOffers: false }
  );
});

test('notification preference patch accepts only one exact boolean field', () => {
  assert.equal(
    parseNotificationPreferencePatch({ productOffers: true }),
    true
  );
  assert.equal(
    parseNotificationPreferencePatch({ productOffers: false }),
    false
  );

  const invalidPayloads = [
    null,
    [],
    {},
    { productOffers: 'true' },
    { productOffers: 1 },
    { productOffers: true, extra: false }
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
    notificationPreferences: { productOffers: true },
    saveCalls: 0,
    async save() {
      this.saveCalls += 1;
    }
  };

  const result = await updateProductOffersPreference({
    user,
    productOffers: false
  });

  assert.equal(user.saveCalls, 1);
  assert.equal(user.notificationPreferences.productOffers, false);
  assert.deepEqual(result, { productOffers: false });
});

test('authoritative update rejects non-boolean values', async () => {
  const user = {
    notificationPreferences: { productOffers: true },
    async save() {
      throw new Error('save must not run');
    }
  };

  await assert.rejects(
    () =>
      updateProductOffersPreference({
        user,
        productOffers: 'false'
      }),
    (error) => {
      assert.equal(error.statusCode, 400);
      assert.equal(error.code, 'INVALID_NOTIFICATION_PREFERENCE');
      return true;
    }
  );
});

test('new User documents default product and offer preference to enabled', () => {
  const user = new User({
    name: 'Preference Test',
    passwordHash: 'not-used-by-this-test'
  });

  assert.equal(user.notificationPreferences.productOffers, true);
});
