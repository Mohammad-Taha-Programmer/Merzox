import assert from 'node:assert/strict';
import test from 'node:test';

import {
  counterpartSenderType,
  lastReceivedByConversation,
  lastReceivedPipeline
} from '../src/policies/conversation-stamp.policy.js';

/// The time an inbox row shows.
///
/// It was the time of the last message in the thread, which is your own reply
/// every time you answer someone - so the row told a merchant when they last
/// spoke rather than when the customer did. Scanning an inbox is deciding how
/// long people have been waiting, and that is the other side's clock.

test('a customer is waiting on the shop', () => {
  assert.equal(counterpartSenderType('customer'), 'business');
});

test('a merchant is waiting on the customer', () => {
  assert.equal(counterpartSenderType('business'), 'customer');
});

test('an unknown viewer is treated as a customer, not as themselves', () => {
  // The one answer that must never come back is the reader's own side: it
  // would put their own reply time on every row.
  assert.notEqual(counterpartSenderType(undefined), 'customer');
});

test('only the other side is looked at', () => {
  const [match] = lastReceivedPipeline(['c1'], 'customer');

  assert.deepEqual(match.$match.senderType, 'customer');
  assert.deepEqual(match.$match.conversation, { $in: ['c1'] });
});

test('the newest of each thread is the one kept', () => {
  const [, sort, group] = lastReceivedPipeline(['c1'], 'business');

  // Newest first, then the first of each group: the last thing they said.
  assert.equal(sort.$sort.createdAt, -1);
  assert.deepEqual(group.$group.at, { $first: '$createdAt' });
  assert.equal(group.$group._id, '$conversation');
});

test('one query answers a whole page, not one per row', () => {
  const pipeline = lastReceivedPipeline(['c1', 'c2', 'c3'], 'customer');

  assert.deepEqual(pipeline[0].$match.conversation.$in, ['c1', 'c2', 'c3']);
});

test('the rows become a lookup keyed by conversation', () => {
  const at = new Date('2026-09-06T09:43:00Z');
  const byId = lastReceivedByConversation([{ _id: 'c1', at }]);

  assert.equal(byId.get('c1'), at);
});

test('an object id is keyed by its string, as the JSON will be', () => {
  const byId = lastReceivedByConversation([
    { _id: { toString: () => 'c9' }, at: null }
  ]);

  assert.equal(byId.has('c9'), true);
});

test('a thread nobody has written to you in is simply absent', () => {
  const byId = lastReceivedByConversation([]);

  // Absent, not zero: "nothing received yet" is not "received at the epoch".
  assert.equal(byId.get('c1'), undefined);
});

test('malformed rows are skipped rather than keyed as null', () => {
  const byId = lastReceivedByConversation([null, {}, { _id: 'c1', at: null }]);

  assert.equal(byId.size, 1);
  assert.equal(byId.get('c1'), null);
});

test('nothing at all is an empty lookup, not a throw', () => {
  assert.equal(lastReceivedByConversation(undefined).size, 0);
});
