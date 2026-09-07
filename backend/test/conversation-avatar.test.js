import assert from 'node:assert/strict';
import test from 'node:test';

import mongoose from 'mongoose';

import { Conversation } from '../src/models/Conversation.js';
import { applyAvatarToConversations } from '../src/services/account-picture.service.js';

/**
 * The picture at the head of a thread, on both sides of it.
 *
 * The customer sees the shop's logo, which has been carried since the shop
 * had one. The merchant saw the first letter of a name: `toMerchantJSON`
 * answered with a blank picture, and nothing was ever stored to answer with.
 */

function thread({ userAvatarUrl } = {}) {
  return new Conversation({
    user: new mongoose.Types.ObjectId(),
    business: new mongoose.Types.ObjectId(),
    userName: 'محمد أمين',
    userAvatarUrl,
    businessName: 'البتول كوزماتيكس',
    businessLogoUrl: 'https://images.test/logo.png'
  });
}

test('each side is shown the other one', () => {
  const conversation = thread({
    userAvatarUrl: 'https://images.test/customer.png'
  });

  // What the customer looks at: the shop.
  assert.equal(
    conversation.toCustomerJSON().avatarUrl,
    'https://images.test/logo.png'
  );

  // What the merchant looks at: the person. This was hard-coded empty, so the
  // header could only ever draw the first letter of the name.
  assert.equal(
    conversation.toMerchantJSON().avatarUrl,
    'https://images.test/customer.png'
  );
  assert.equal(
    conversation.toMerchantJSON().customer.avatarUrl,
    'https://images.test/customer.png'
  );
});

test('an account with no picture is an empty string, not a hole', () => {
  // The header draws the initial then, which is the right answer for someone
  // who has set no picture - and the app tells the two apart by emptiness.
  const conversation = thread();

  assert.equal(conversation.toMerchantJSON().avatarUrl, '');
  assert.equal(conversation.toMerchantJSON().customer.avatarUrl, '');
});

test('changing a picture reaches every thread that shows it', async () => {
  // The copy exists so a merchant's inbox costs one query rather than one per
  // row. Nothing refreshed it, which is the same defect the shop's logo had.
  const calls = [];
  const model = {
    async updateMany(filter, update) {
      calls.push({ filter, update });
      return { modifiedCount: 3 };
    }
  };

  const userId = new mongoose.Types.ObjectId();
  const moved = await applyAvatarToConversations(
    userId,
    'https://images.test/new.png',
    { model }
  );

  assert.equal(moved, 3);
  assert.deepEqual(calls, [
    {
      filter: { user: userId },
      update: { $set: { userAvatarUrl: 'https://images.test/new.png' } }
    }
  ]);
});

test('a picture that was removed clears the copy rather than keeping it', async () => {
  const calls = [];
  const model = {
    async updateMany(filter, update) {
      calls.push(update);
      return { modifiedCount: 1 };
    }
  };

  await applyAvatarToConversations(new mongoose.Types.ObjectId(), null, {
    model
  });

  assert.deepEqual(calls, [{ $set: { userAvatarUrl: '' } }]);
});

test('an anonymous caller writes to nothing', async () => {
  let touched = false;
  const model = {
    async updateMany() {
      touched = true;
      return { modifiedCount: 0 };
    }
  };

  assert.equal(await applyAvatarToConversations(null, 'x', { model }), 0);
  assert.equal(touched, false);
});
