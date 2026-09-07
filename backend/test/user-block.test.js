import assert from 'node:assert/strict';
import test from 'node:test';

import mongoose from 'mongoose';

import { UserBlock } from '../src/models/UserBlock.js';
import {
  assertBlockableCounterpart,
  assertNotBlocked,
  conversationCounterpart,
  USER_BLOCK_CODES
} from '../src/policies/user-block.policy.js';

/**
 * Refusing to hear from someone.
 *
 * Who is blocked is never asked for. A block is made from inside a
 * conversation, so the other side of that conversation is the only person it
 * can name - the same shape as sharing a product into a thread, and for the
 * same reason: there is no id to forge.
 */

const customer = new mongoose.Types.ObjectId();
const owner = new mongoose.Types.ObjectId();

function conversation() {
  return { user: customer, business: new mongoose.Types.ObjectId() };
}

test('each side faces the other, and neither names them', () => {
  // The customer faces whoever owns the shop.
  assert.equal(
    conversationCounterpart({
      conversation: conversation(),
      viewerType: 'customer',
      businessOwnerId: owner
    }),
    owner
  );

  // The merchant faces the customer the thread belongs to.
  assert.equal(
    conversationCounterpart({
      conversation: conversation(),
      viewerType: 'business'
    }),
    customer
  );
});

test('a shop with no owner leaves nobody to block', () => {
  // The data allows it, and an absence is not an error until something tries
  // to act on it.
  const nobody = conversationCounterpart({
    conversation: conversation(),
    viewerType: 'customer',
    businessOwnerId: null
  });

  assert.equal(nobody, null);

  try {
    assertBlockableCounterpart(customer, nobody);
    assert.fail('a block was made against nobody');
  } catch (error) {
    assert.equal(error.statusCode, 404);
  }
});

test('an account cannot close the door on itself', () => {
  try {
    assertBlockableCounterpart(customer, customer);
    assert.fail('an account blocked itself');
  } catch (error) {
    assert.equal(error.code, USER_BLOCK_CODES.self);
    assert.equal(error.statusCode, 400);
  }

  assert.equal(assertBlockableCounterpart(customer, owner), owner);
});

test('a closed door stops a message in both directions', () => {
  // Letting the one who blocked keep writing would turn a refusal to hear
  // into a way to speak unanswerable.
  for (const state of [
    { blockedByMe: true, blockedMe: false },
    { blockedByMe: false, blockedMe: true },
    { blockedByMe: true, blockedMe: true }
  ]) {
    try {
      assertNotBlocked(state);
      assert.fail(`a message crossed ${JSON.stringify(state)}`);
    } catch (error) {
      assert.equal(error.code, USER_BLOCK_CODES.blocked);
      assert.equal(error.statusCode, 403);
      // Worded for the sender rather than about the other person: it says
      // what to expect without saying what somebody else did.
      assert.match(error.message, /closed/);
    }
  }
});

test('an open door carries the message', () => {
  assert.equal(
    assertNotBlocked({ blockedByMe: false, blockedMe: false }),
    undefined
  );
});

test('blocking twice is one block', () => {
  // The index is what makes it so, rather than a check that could race with a
  // second tap.
  const index = UserBlock.schema
    .indexes()
    .find(([, options]) => options?.name === 'unique_block_pair');

  assert.ok(index, 'the unique index is missing');
  assert.deepEqual(index[0], { blocker: 1, blocked: 1 });
  assert.equal(index[1].unique, true);
});

test('a block records the pair and nothing else', () => {
  // No reason, no note, no expiry: none of them changes what the app does,
  // and a field no screen can set or show is a promise the code does not
  // keep.
  const paths = Object.keys(UserBlock.schema.paths).sort();

  assert.deepEqual(paths, [
    '__v',
    '_id',
    'blocked',
    'blocker',
    'createdAt',
    'updatedAt'
  ]);
});
