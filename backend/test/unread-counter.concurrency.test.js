import assert from 'node:assert/strict';
import test from 'node:test';

import mongoose from 'mongoose';

import {
  acknowledgementFilter,
  acknowledgementUpdate,
  applyAcknowledgement,
  applyIncrement,
  isNoOpAcknowledgement
} from '../src/policies/unread-counter.policy.js';

/**
 * FIX3-A concurrency proof.
 *
 * MongoDB applies each update document atomically, so the question these tests
 * answer is whether the two writers - a sender incrementing and a reader
 * acknowledging - can be interleaved in any order without losing a write.
 *
 * `applyIncrement` and `applyAcknowledgement` are the exact arithmetic the
 * database performs (`$inc` on the sender side, the `$max/$subtract` pipeline
 * on the reader side), so applying them in different orders is a faithful
 * model of two concurrent atomic updates racing.
 */

/** Evaluates the real reader-side pipeline the way the server would. */
function evaluatePipeline(current, field, modifiedCount) {
  const [stage] = acknowledgementUpdate(field, modifiedCount);
  const expression = stage.$set[field];
  const [floor, subtract] = expression.$max;
  const [fieldRef, acknowledged] = subtract.$subtract;

  assert.equal(fieldRef, `$${field}`, 'pipeline must subtract from the field');
  return Math.max(floor, current - acknowledged);
}

test('CASE 1: three unread, two acknowledged, counter becomes one', () => {
  assert.equal(applyAcknowledgement(3, 2), 1);
  assert.equal(evaluatePipeline(3, 'unreadForUser', 2), 1);
});

test('CASE 2: a sender increment before the reader decrement survives', () => {
  // unread = 3, sender +1 -> 4, reader acknowledges the 2 it actually saw -> 2
  const afterSender = applyIncrement(3);
  assert.equal(afterSender, 4);

  const final = applyAcknowledgement(afterSender, 2);
  assert.equal(final, 2, 'the new message must still be counted');
});

test('CASE 3: a sender increment after the reader decrement survives', () => {
  // unread = 3, reader acknowledges 2 -> 1, sender +1 -> 2
  const afterReader = applyAcknowledgement(3, 2);
  assert.equal(afterReader, 1);

  const final = applyIncrement(afterReader);
  assert.equal(final, 2, 'the new message must still be counted');
});

test('the two writers commute for every interleaving', () => {
  // Order independence is the whole point: whichever update reaches the
  // database first, the result is identical.
  for (let unread = 0; unread <= 5; unread++) {
    for (let acknowledged = 0; acknowledged <= unread; acknowledged++) {
      const senderFirst = applyAcknowledgement(
        applyIncrement(unread),
        acknowledged
      );
      const readerFirst = applyIncrement(
        applyAcknowledgement(unread, acknowledged)
      );

      assert.equal(
        senderFirst,
        readerFirst,
        `unread=${unread} acknowledged=${acknowledged} must not depend on order`
      );
      assert.equal(senderFirst, unread - acknowledged + 1);
    }
  }
});

test('the rejected recount-and-set approach loses the increment', () => {
  // Kept as a regression witness: this is the bug FIX3-A removes. The reader
  // counts what remains (0), a sender increments to 1, and the reader then
  // overwrites the counter with its stale count.
  const staleRecount = 0;
  const afterSender = applyIncrement(0);
  assert.equal(afterSender, 1);

  const lostUpdate = staleRecount; // $set: { unread: staleRecount }
  assert.equal(lostUpdate, 0);

  // The delta form cannot express that mistake: nothing was acknowledged, so
  // nothing is subtracted.
  assert.equal(applyAcknowledgement(afterSender, 0), 1);
});

test('CASE 4: a message created after the cutoff is outside the filter', () => {
  const readThrough = new Date('2026-02-18T09:43:00.000Z');
  const conversationId = new mongoose.Types.ObjectId();

  const filter = acknowledgementFilter({
    conversationId,
    counterpartSenderType: 'business',
    readThrough
  });

  assert.equal(filter.readAt, null);
  assert.equal(filter.senderType, 'business');
  assert.equal(filter.conversation, conversationId);
  assert.deepEqual(filter.createdAt, { $lte: readThrough });

  // Applying the same predicate the server hands to MongoDB.
  const matches = (message) =>
    String(message.conversation) === String(filter.conversation) &&
    message.senderType === filter.senderType &&
    message.readAt === null &&
    message.createdAt <= filter.createdAt.$lte;

  const before = {
    conversation: conversationId,
    senderType: 'business',
    readAt: null,
    createdAt: new Date('2026-02-18T09:42:59.000Z')
  };
  const exactlyAtCutoff = { ...before, createdAt: readThrough };
  const after = {
    ...before,
    createdAt: new Date('2026-02-18T09:43:00.001Z')
  };

  assert.equal(matches(before), true, 'an older message is acknowledged');
  assert.equal(matches(exactlyAtCutoff), true, 'the cutoff is inclusive');
  assert.equal(
    matches(after),
    false,
    'a message that arrived mid-request must not be acknowledged'
  );

  // The reader's own messages are never acknowledged on their behalf.
  assert.equal(matches({ ...before, senderType: 'customer' }), false);
  // Already-read messages are not re-acknowledged, so they cannot double-count.
  assert.equal(matches({ ...before, readAt: new Date() }), false);
});

test('CASE 5: an empty acknowledgement leaves the counter untouched', () => {
  assert.equal(isNoOpAcknowledgement(0), true);
  assert.equal(applyAcknowledgement(3, 0), 3);
  assert.equal(evaluatePipeline(3, 'unreadForBusiness', 0), 3);

  // A message that arrived after the cutoff keeps its badge even though the
  // reader just acknowledged the thread.
  assert.equal(applyAcknowledgement(applyIncrement(0), 0), 1);
});

test('CASE 6: the counter can never go negative', () => {
  assert.equal(applyAcknowledgement(0, 5), 0);
  assert.equal(applyAcknowledgement(2, 5), 0);
  assert.equal(evaluatePipeline(2, 'unreadForUser', 5), 0);

  // Even from an already-corrupt negative value the clamp holds.
  assert.equal(applyAcknowledgement(-3, 1), 0);
  assert.equal(applyIncrement(-3), 1);
});

test('non-numeric or malformed counts degrade safely', () => {
  for (const bogus of [undefined, null, NaN, 'two', {}, -1]) {
    assert.equal(applyAcknowledgement(3, bogus), 3, `acknowledged=${bogus}`);
    assert.equal(isNoOpAcknowledgement(bogus), true, `noop=${bogus}`);
  }

  assert.equal(applyAcknowledgement(undefined, 2), 0);
  assert.equal(applyIncrement(undefined), 1);
});

test('the reader update is a delta pipeline, never an absolute set', () => {
  const pipeline = acknowledgementUpdate('unreadForUser', 2);

  assert.equal(Array.isArray(pipeline), true, 'must be an aggregation pipeline');
  assert.equal(pipeline.length, 1, 'a single atomic stage');

  const expression = pipeline[0].$set.unreadForUser;
  assert.ok(expression.$max, 'must clamp at zero inside the same update');
  assert.ok(expression.$max[1].$subtract, 'must subtract, not assign');
  assert.equal(
    typeof expression.$max[1].$subtract[0],
    'string',
    'must read the current value from the document'
  );
  assert.equal(expression.$max[1].$subtract[0], '$unreadForUser');
  assert.equal(expression.$max[1].$subtract[1], 2);
});
