import assert from 'node:assert/strict';
import test from 'node:test';

import {
  MESSAGE_NOTIFICATION_TYPE,
  bellNotificationFilter
} from '../src/policies/notification-audience.policy.js';

/// What the bell speaks for.
///
/// A new message writes a notification record, and the bell counted it - so
/// one message from one customer put a `1` on the bell and a `1` on the
/// messages icon at the same moment, for the same event. Two counts and one
/// thing to do, with no way to tell they were the same thing.
///
/// The messages icon owns messages. The record is still written, because push
/// delivery and the history both need it; it simply is not the bell's.

test('the bell excludes message notifications', () => {
  const filter = bellNotificationFilter({ user: 'u1', audience: 'business' });

  assert.deepEqual(filter.type, { $ne: MESSAGE_NOTIFICATION_TYPE });
});

test('it keeps everything else the caller asked for', () => {
  const filter = bellNotificationFilter({
    user: 'u1',
    audience: 'customer',
    readAt: null
  });

  assert.equal(filter.user, 'u1');
  assert.equal(filter.audience, 'customer');
  assert.equal(filter.readAt, null);
});

test('it does not narrow the filter it was given', () => {
  // One base filter is reused for several counts in the listing. Mutating it
  // here would silently narrow all of them, including ones that must not be.
  const base = { user: 'u1', audience: 'business' };
  bellNotificationFilter(base);

  assert.equal('type' in base, false);
});

test('an empty filter still excludes messages', () => {
  assert.deepEqual(bellNotificationFilter().type, {
    $ne: MESSAGE_NOTIFICATION_TYPE
  });
});

test('the excluded type is the one the message service writes', () => {
  // Stated here so a rename on either side breaks loudly rather than quietly
  // putting message counts back on the bell.
  assert.equal(MESSAGE_NOTIFICATION_TYPE, 'newMessage');
});
