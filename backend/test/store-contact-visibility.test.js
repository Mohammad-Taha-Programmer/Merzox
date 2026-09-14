import assert from 'node:assert/strict';
import test from 'node:test';

import mongoose from 'mongoose';

import { Business } from '../src/models/Business.js';
import { validateBusinessProfilePatch } from '../src/middleware/validate.js';

/**
 * Whether a customer may see the merchant's own number and address.
 *
 * The social links beside them were typed into store settings to be
 * published. A phone and an email were not: they were given at sign-up to
 * open an account. So this permission exists, it is off until the owner turns
 * it on, and these tests are about the ways it could leak rather than about
 * the way it works.
 */

function shop(overrides = {}) {
  return new Business({
    owner: new mongoose.Types.ObjectId(),
    publicId: 'MXB-CONTACT-0001',
    name: 'متجر البتول',
    category: 'مستحضرات تجميل',
    ...overrides
  });
}

const account = {
  phones: [
    { value: '+972590000001', label: 'mobile', isPrimary: true },
    { value: '022345678', label: 'work' }
  ],
  emails: [{ value: 'shop@example.test', label: 'work' }]
};

test('a shop publishes no owner contact until its owner says so', () => {
  const business = shop();

  assert.equal(business.showOwnerContact, false);

  // The account is in hand and still nothing travels: it is the permission
  // that decides, not whether the caller happened to load the owner.
  const detail = business.toDetailJSON(account);
  assert.deepEqual(detail.contact, { phones: [], emails: [] });
});

test('a shop that said yes publishes the account it reads, not a copy', () => {
  const detail = shop({ showOwnerContact: true }).toDetailJSON(account);

  assert.deepEqual(detail.contact.phones, [
    { value: '+972590000001', label: 'mobile' },
    { value: '022345678', label: 'work' }
  ]);
  assert.deepEqual(detail.contact.emails, [
    { value: 'shop@example.test', label: 'work' }
  ]);

  // Which number the merchant marked first is theirs to know. A customer
  // needs the ones they can call and nothing about how they are ordered.
  for (const phone of detail.contact.phones) {
    assert.equal(phone.isPrimary, undefined);
  }
});

test('forgetting the owner publishes nothing rather than everything', () => {
  // `toDetailJSON` takes the account as an argument instead of reading it off
  // the shop, so a caller that never loaded it cannot publish it by accident.
  // This asserts which way that mistake falls.
  const detail = shop({ showOwnerContact: true }).toDetailJSON();

  assert.deepEqual(detail.contact, { phones: [], emails: [] });
});

test('an account with only the single email is still reachable', () => {
  // `email` still sits beside `emails`, so an account that carries only the
  // one it was opened with is published rather than shown as having given
  // nothing.
  const detail = shop({ showOwnerContact: true }).toDetailJSON({
    email: 'old@example.test'
  });

  assert.deepEqual(detail.contact.emails, [
    { value: 'old@example.test', label: 'personal' }
  ]);
});

test('a number is published from the list and from nowhere else', () => {
  // The single `phone` is gone: it held a copy of the list's first entry, so
  // there is no second place a number could come from. An account with an
  // empty list has no number to publish, and a stray `phone` on the object -
  // a document from before the field was dropped - is not one either.
  const detail = shop({ showOwnerContact: true }).toDetailJSON({
    phone: '+972590000009',
    phones: []
  });

  assert.deepEqual(detail.contact.phones, []);

  const listed = shop({ showOwnerContact: true }).toDetailJSON({
    phones: [{ value: ' +972590000009 ', label: 'mobile' }]
  });

  assert.deepEqual(listed.contact.phones, [
    { value: '+972590000009', label: 'mobile' }
  ]);
});

test('an empty entry is left out rather than published blank', () => {
  const detail = shop({ showOwnerContact: true }).toDetailJSON({
    phones: [{ value: '   ', label: 'mobile' }, { value: '0599', label: 'home' }],
    emails: []
  });

  assert.deepEqual(detail.contact.phones, [
    { value: '0599', label: 'home' }
  ]);
  assert.deepEqual(detail.contact.emails, []);
});

test('the merchant screen is told the permission, not the numbers behind it', () => {
  const owner = shop({ showOwnerContact: true }).toOwnerJSON();

  assert.equal(owner.showOwnerContact, true);
  // The merchant is signed in as the account these come from, so the shop
  // has no reason to hand them back a second time.
  assert.deepEqual(owner.contact, { phones: [], emails: [] });
});

test('the permission is a boolean or it is refused', () => {
  let passed = false;
  validateBusinessProfilePatch(
    { body: { showOwnerContact: true } },
    undefined,
    () => {
      passed = true;
    }
  );
  assert.equal(passed, true);

  // `"false"` is truthy. A string that looks like an answer is the way this
  // could publish a number after the merchant said no, so it is refused at
  // the edge rather than coerced somewhere behind it.
  for (const value of ['false', 'true', 1, 0, null]) {
    assert.throws(
      () =>
        validateBusinessProfilePatch(
          { body: { showOwnerContact: value } },
          undefined,
          () => {}
        ),
      (error) => {
        assert.equal(error.statusCode, 400);
        assert.equal(error.code, 'INVALID_OWNER_CONTACT_PERMISSION');
        return true;
      },
      `${JSON.stringify(value)} should be refused`
    );
  }
});
