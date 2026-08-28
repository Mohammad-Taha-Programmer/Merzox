import assert from 'node:assert/strict';
import test from 'node:test';

import { updateMe } from '../src/controllers/user.controller.js';
import { User } from '../src/models/User.js';
import {
  formatBirthDate,
  parseBirthDate
} from '../src/policies/birth-date.policy.js';

/**
 * The birth-date slice is exercised against the real model document and the
 * real controller, without a database: `toSafeJSON` is the published contract
 * and `updateMe` is the only writer. Persistence is stubbed so the test proves
 * field authority rather than Mongo behaviour.
 */
function buildUser(overrides = {}) {
  const user = new User({
    name: 'ليان',
    passwordHash: 'x',
    ...overrides
  });

  user.save = async () => user;

  return user;
}

/**
 * `updateMe` is wrapped in `asyncHandler`, which routes a rejection to `next`
 * rather than to the caller. The handler contract is restored here so a test
 * can await either outcome.
 */
function runUpdateMe(user, body) {
  return new Promise((resolve, reject) => {
    updateMe(
      { user, body },
      {
        json(payload) {
          resolve(payload);
        }
      },
      reject
    );
  });
}

test('safe JSON exposes a stored birth date as a date-only string', () => {
  const user = buildUser({ birthDate: new Date(Date.UTC(2000, 1, 29)) });

  const safe = user.toSafeJSON();

  assert.equal(safe.birthDate, '2000-02-29');
  // A full ISO timestamp would invite a client timezone conversion that moves
  // the calendar day.
  assert.equal(safe.birthDate.includes('T'), false);
});

test('a legacy account without a birth date reports null', () => {
  const user = buildUser();

  assert.equal(user.birthDate, null);
  assert.equal(user.toSafeJSON().birthDate, null);
});

test('a stored UTC midnight date never drifts across a day boundary', () => {
  // 1994-11-07T00:00:00Z is the exact instant the normalizer writes.
  const user = buildUser({ birthDate: new Date('1994-11-07T00:00:00.000Z') });

  assert.equal(user.toSafeJSON().birthDate, '1994-11-07');
});

test('the profile update normalizes a birth date to UTC midnight', async () => {
  const user = buildUser();

  const payload = await runUpdateMe(user, { birthDate: '2000-02-29' });

  assert.equal(user.birthDate.toISOString(), '2000-02-29T00:00:00.000Z');
  assert.equal(payload.data.user.birthDate, '2000-02-29');
});

test('the profile update may clear a birth date with an explicit null', async () => {
  const user = buildUser({ birthDate: new Date(Date.UTC(1994, 10, 7)) });

  const payload = await runUpdateMe(user, { birthDate: null });

  assert.equal(user.birthDate, null);
  assert.equal(payload.data.user.birthDate, null);
});

test('updating an unrelated profile field never invents a birth date', async () => {
  const user = buildUser();

  const payload = await runUpdateMe(user, {
    address: 'رام الله ، دوار المنارة'
  });

  assert.equal(user.address, 'رام الله ، دوار المنارة');
  assert.equal(user.birthDate, null);
  assert.equal(payload.data.user.birthDate, null);
});

test('an omitted birth date leaves a stored one untouched', async () => {
  const user = buildUser({ birthDate: new Date(Date.UTC(1994, 10, 7)) });

  await runUpdateMe(user, { address: 'نابلس' });

  assert.equal(user.toSafeJSON().birthDate, '1994-11-07');
});

test('the birth date carries no one-time-change restriction', async () => {
  const user = buildUser({ birthDate: new Date(Date.UTC(1994, 10, 7)) });

  await runUpdateMe(user, { birthDate: '1995-01-01' });
  await runUpdateMe(user, { birthDate: '1996-06-30' });

  assert.equal(user.toSafeJSON().birthDate, '1996-06-30');
  // Only name and gender are once-only, and neither was touched.
  assert.equal(user.nameChangedAt, null);
  assert.equal(user.genderChangedAt, null);
});

test('the controller refuses an impossible date even without the validator', async () => {
  const user = buildUser();

  await assert.rejects(
    runUpdateMe(user, { birthDate: '2026-02-30' }),
    (error) => error.code === 'INVALID_BIRTH_DATE' && error.statusCode === 400
  );

  assert.equal(user.birthDate, null);
});

test('the policy round-trips every canonical date it accepts', () => {
  for (const value of ['2000-02-29', '1994-11-07', '1900-01-01', '2024-12-31']) {
    assert.equal(formatBirthDate(parseBirthDate(value)), value);
  }
});

/**
 * The year selector offers every Gregorian year down to 1, so the policy has to
 * mean year 1 when it is told year 1. `Date.UTC(1, 0, 1)` means 1901, which is
 * why these low years get their own coverage.
 */
test('a year below 0100 keeps its literal Gregorian value', () => {
  for (const value of ['0001-01-01', '0099-12-31', '0100-01-01']) {
    const parsed = parseBirthDate(value);

    assert.ok(parsed, `${value} should parse`);
    assert.equal(formatBirthDate(parsed), value);
    assert.equal(parsed.getUTCFullYear(), Number(value.slice(0, 4)));
    // The 1900 window would have produced 1901-01-01T00:00:00.000Z here.
    assert.equal(parsed.getUTCHours(), 0);
    assert.equal(parsed.getUTCMinutes(), 0);
    assert.equal(parsed.getUTCSeconds(), 0);
    assert.equal(parsed.getUTCMilliseconds(), 0);
  }
});

test('year 0000 is not a birth year', () => {
  assert.equal(parseBirthDate('0000-01-01'), null);
  assert.equal(parseBirthDate('0000-12-31'), null);
});

test('the calendar still rules in the low years', () => {
  // Year 1 is not a leap year; year 4 is.
  assert.equal(parseBirthDate('0001-02-29'), null);
  assert.equal(formatBirthDate(parseBirthDate('0004-02-29')), '0004-02-29');
  // Malformed shapes stay refused whatever the year.
  assert.equal(parseBirthDate('1-01-01'), null);
  assert.equal(parseBirthDate('0001-13-01'), null);
});

test('safe JSON emits a low year as a four-digit canonical date', () => {
  const user = buildUser({ birthDate: parseBirthDate('0099-12-31') });

  assert.equal(user.toSafeJSON().birthDate, '0099-12-31');
  assert.equal(user.toSafeJSON().birthDate.includes('T'), false);
});

test('the profile update persists a low year without a 1900 offset', async () => {
  const user = buildUser();

  const payload = await runUpdateMe(user, { birthDate: '0001-01-01' });

  assert.equal(user.birthDate.getUTCFullYear(), 1);
  assert.notEqual(user.birthDate.getUTCFullYear(), 1901);
  assert.equal(payload.data.user.birthDate, '0001-01-01');

  const later = await runUpdateMe(user, { birthDate: '0099-12-31' });

  assert.equal(user.birthDate.getUTCFullYear(), 99);
  assert.notEqual(user.birthDate.getUTCFullYear(), 1999);
  assert.equal(later.data.user.birthDate, '0099-12-31');
});
