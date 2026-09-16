import assert from 'node:assert/strict';
import test from 'node:test';

import {
  phoneMatches,
  phoneSearchDigits,
  phoneSearchPattern
} from '../src/policies/phone-search.policy.js';

/**
 * One telephone, several ways of writing it.
 *
 * The account stores one spelling and the customer types another, and neither
 * of them chose which. What they share is the end of the number.
 */

test('the country and the trunk zero come off, the subscriber stays', () => {
  assert.equal(phoneSearchDigits('0592029316'), '592029316');
  assert.equal(phoneSearchDigits('+970592029316'), '970592029316');
  assert.equal(phoneSearchDigits('00970592029316'), '970592029316');
  assert.equal(phoneSearchDigits('+970 59 202 9316'), '970592029316');
});

test('a name that happens to carry digits is not a number', () => {
  assert.equal(phoneSearchDigits('متجر مرزوكس التجريبي 083'), null);
  assert.equal(phoneSearchDigits('shop 0592029316'), null);
});

test('too few digits to be a number is not a number', () => {
  // `083` would otherwise find every shop whose owner's number ends in it.
  assert.equal(phoneSearchDigits('083'), null);
  assert.equal(phoneSearchDigits('0'), null);
  assert.equal(phoneSearchDigits(''), null);
  assert.equal(phoneSearchDigits('123456'), null);
  assert.equal(phoneSearchDigits('1234567'), '1234567');
});

test('the local form finds the international one, and the reverse', () => {
  const stored = '+970592029316';

  for (const typed of [
    '0592029316',
    '+970592029316',
    '00970592029316',
    '970592029316',
    '059 202 9316'
  ]) {
    assert.equal(
      phoneMatches(stored, phoneSearchDigits(typed)),
      true,
      `"${typed}" did not find "${stored}"`
    );
  }
});

test('a number stored with separators is the same number', () => {
  assert.equal(
    phoneMatches('+970 59 202 9316', phoneSearchDigits('0592029316')),
    true
  );
});

test('a different number is a different number', () => {
  const digits = phoneSearchDigits('0592029316');

  assert.equal(phoneMatches('+970599000000', digits), false);
  assert.equal(phoneMatches('+970592029317', digits), false);
  assert.equal(phoneMatches('', digits), false);
  assert.equal(phoneMatches('+970592029316', null), false);
});

test('the pattern finds the number at the end and not in the middle', () => {
  const pattern = phoneSearchPattern(phoneSearchDigits('0592029316'));

  assert.equal(pattern.test('+970592029316'), true);
  assert.equal(pattern.test('+970 59 202 9316'), true);
  assert.equal(pattern.test('+9705920293160'), false);
});

test('the pattern carries nothing a second dialect would read differently', () => {
  // It is executed by MongoDB, which reads PCRE - the lesson the Arabic
  // patterns cost a merchant their findability to learn.
  const pattern = phoneSearchPattern(phoneSearchDigits('+970592029316'));

  assert.equal(/\\u[0-9A-Fa-f]{4}|\\[pP]\{|\(\?<[A-Za-z]/.test(pattern.source), false);
});

test('no digits, no pattern', () => {
  assert.equal(phoneSearchPattern(null), null);
  assert.equal(phoneSearchPattern(''), null);
});
