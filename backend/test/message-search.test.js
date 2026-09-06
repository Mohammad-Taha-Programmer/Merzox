import assert from 'node:assert/strict';
import test from 'node:test';

import {
  MAX_MATCHES_PER_CONVERSATION,
  MAX_QUERY_LENGTH,
  groupMessageHits,
  normalizeSearchQuery,
  searchPattern
} from '../src/policies/message-search.policy.js';

/// Searching the messages.
///
/// Two questions share one box. A name should offer the thread; a phrase
/// should offer the place it was said - and the place must be the FIRST time
/// it was said, because stepping forward with the arrows should walk the
/// conversation the way it happened rather than backwards from the end.

function hit(id, conversation, body, minutes) {
  return {
    _id: id,
    conversation,
    body,
    createdAt: new Date(Date.UTC(2026, 8, 6, 9, minutes))
  };
}

test('a blank query stays blank rather than becoming a match-all', () => {
  // The controller answers an empty query with empty results. If this trimmed
  // to something truthy, an empty search box would return every message.
  assert.equal(normalizeSearchQuery('   '), '');
  assert.equal(normalizeSearchQuery(null), '');
  assert.equal(normalizeSearchQuery(undefined), '');
});

test('a query is cut to a length a person could have typed', () => {
  const long = 'ا'.repeat(500);

  assert.equal(normalizeSearchQuery(long).length, MAX_QUERY_LENGTH);
});

test('a bracket is looked for, not compiled', () => {
  // Someone searching for "(2" is looking for a bracket. Unescaped this is an
  // unterminated group: a 500, not a result.
  const pattern = searchPattern('(2');

  assert.equal(pattern.test('order (2) is ready'), true);
  assert.equal(pattern.test('order 2 is ready'), false);
});

test('a search ignores case', () => {
  assert.equal(searchPattern('order').test('ORDER shipped'), true);
});

test('Arabic is matched as typed', () => {
  assert.equal(searchPattern('الطلبية').test('قديه بدها الطلبية لتوصلني؟'), true);
});

test('one word said nine times is one row with a count of nine', () => {
  const hits = [];
  for (let index = 0; index < 9; index += 1) {
    hits.push(hit(`m${index}`, 'c1', 'الطلبية', index));
  }

  const [row] = groupMessageHits(hits);

  assert.equal(groupMessageHits(hits).length, 1);
  assert.equal(row.matchCount, 9);
});

test('the row opens at the first time it was said', () => {
  const hits = [
    hit('older', 'c1', 'وين الطلبية', 1),
    hit('newer', 'c1', 'الطلبية وصلت', 40)
  ];

  const [row] = groupMessageHits(hits);

  // Step 1 of the counter, and where the chat scrolls to.
  assert.equal(row.matchIds[0], 'older');
  assert.equal(row.snippet, 'وين الطلبية');
});

test('the arrows walk forward in the order it happened', () => {
  const hits = [
    hit('a', 'c1', 'الطلبية', 1),
    hit('b', 'c1', 'الطلبية', 5),
    hit('c', 'c1', 'الطلبية', 9)
  ];

  assert.deepEqual(groupMessageHits(hits)[0].matchIds, ['a', 'b', 'c']);
});

test('the thread that was talking most recently comes first', () => {
  const hits = [
    hit('a', 'quiet', 'الطلبية', 1),
    hit('b', 'busy', 'الطلبية', 50)
  ];

  assert.deepEqual(
    groupMessageHits(hits).map((row) => row.conversationId),
    ['busy', 'quiet']
  );
});

test('past the ceiling the count keeps counting, the walk stops', () => {
  // The counter and its two arrows are only usable while the number is small.
  // Saying "50" when there are 80 would be a lie; offering 80 steps is not a
  // feature. So: an honest count, and fifty places to stand.
  const hits = [];
  for (let index = 0; index < MAX_MATCHES_PER_CONVERSATION + 30; index += 1) {
    hits.push(hit(`m${index}`, 'c1', 'الطلبية', index));
  }

  const [row] = groupMessageHits(hits);

  assert.equal(row.matchCount, MAX_MATCHES_PER_CONVERSATION + 30);
  assert.equal(row.matchIds.length, MAX_MATCHES_PER_CONVERSATION);
});

test('nothing found is an empty list, not a throw', () => {
  assert.deepEqual(groupMessageHits([]), []);
  assert.deepEqual(groupMessageHits(undefined), []);
});

test('a hit with no timestamp still groups', () => {
  // Older rows predate `timestamps` being switched on. They must not sort the
  // whole result into a throw.
  const rows = groupMessageHits([
    { _id: 'm1', conversation: 'c1', body: 'الطلبية' }
  ]);

  assert.equal(rows.length, 1);
  assert.equal(rows[0].firstMatchAt, null);
});
