import assert from 'node:assert/strict';
import test from 'node:test';

import { User } from '../src/models/User.js';

/**
 * One number field on an account.
 *
 * There were two: a `phones` list and a single `phone` string holding a copy
 * of its first entry, set in the same breath by every path that touched
 * either. Two fields holding one fact is two fields that can disagree, and the
 * only question about them was which one a given piece of code happened to
 * read.
 *
 * What is left is the list, plus `primaryPhone` for the places that need the
 * number singular. This exercises the real model document without a database:
 * the virtual and `toSafeJSON` are the whole of the published contract.
 */
function buildUser(overrides = {}) {
  return new User({ name: 'ليان', passwordHash: 'x', ...overrides });
}

test('an account with no number has none', () => {
  assert.equal(buildUser().primaryPhone, null);
});

test('one number is the number', () => {
  const user = buildUser({
    phones: [{ value: '+970592029316', label: 'mobile' }]
  });

  assert.equal(user.primaryPhone, '+970592029316');
});

test('the one marked primary is the one, wherever it sits', () => {
  const user = buildUser({
    phones: [
      { value: '+970592029316', label: 'work' },
      { value: '+970599000000', label: 'mobile', isPrimary: true }
    ]
  });

  assert.equal(user.primaryPhone, '+970599000000');
});

test('with none marked, the first stands for the account', () => {
  const user = buildUser({
    phones: [
      { value: '+970592029316', label: 'work' },
      { value: '+970599000000', label: 'home' }
    ]
  });

  assert.equal(user.primaryPhone, '+970592029316');
});

test('the single phone is gone from the schema and from the wire', () => {
  // Assigning it is a no-op on a document whose schema does not declare it,
  // which is what says the field is really gone rather than merely unused.
  const user = buildUser({
    phones: [{ value: '+970592029316', label: 'mobile' }]
  });
  user.phone = '+970111111111';

  assert.equal(user.get('phone'), undefined);

  const published = user.toSafeJSON();

  assert.equal(
    Object.prototype.hasOwnProperty.call(published, 'phone'),
    false,
    'toSafeJSON still publishes a single phone'
  );
  assert.equal(published.phones.length, 1);
  assert.equal(published.phones[0].value, '+970592029316');
});
