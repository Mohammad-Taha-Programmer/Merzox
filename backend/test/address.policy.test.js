import assert from 'node:assert/strict';
import test from 'node:test';

import {
  ADDRESS_LIMITS,
  MAX_ADDRESSES,
  buildAddressWrite,
  deliveryRegions,
  findRegion,
  formatAddressLine,
  normalizeDefaults
} from '../src/policies/address.policy.js';

// The address book of `تفاصيل المتجر – 16` and `– 25`, and the region pickers
// of `– 27` and `– 28`.
//
// Two properties carry the weight here: a client cannot write a field it does
// not own, and the book always has exactly one default.

const VALID = {
  label: 'البيت',
  fullName: 'ياسمين خالد',
  phone: '0592029316',
  altPhone: '',
  governorate: 'أريحا',
  city: 'أريحا',
  details: 'شارع القدس'
};

test('a well-formed address is accepted whole', () => {
  const write = buildAddressWrite(VALID);

  assert.equal(write.fullName, 'ياسمين خالد');
  assert.equal(write.governorate, 'أريحا');
  assert.equal(write.city, 'أريحا');
  assert.equal(write.isDefault, false);
});

test('the write is a rebuild, so an unlisted field cannot ride along', () => {
  const write = buildAddressWrite({
    ...VALID,
    // None of these are the client's to set.
    _id: '64a000000000000000000001',
    user: '64a000000000000000000002',
    createdAt: '1999-01-01',
    isVerified: true
  });

  assert.deepEqual(Object.keys(write).sort(), [
    'altPhone',
    'city',
    'details',
    'fullName',
    'governorate',
    'isDefault',
    'label',
    'phone'
  ]);
});

test('a name outside its bounds is refused', () => {
  assert.throws(() => buildAddressWrite({ ...VALID, fullName: 'ي' }), {
    code: 'INVALID_ADDRESS_NAME'
  });
  assert.throws(
    () =>
      buildAddressWrite({
        ...VALID,
        fullName: 'ي'.repeat(ADDRESS_LIMITS.fullNameMax + 1)
      }),
    { code: 'INVALID_ADDRESS_NAME' }
  );
});

test('a phone that cannot be dialled is refused', () => {
  assert.throws(() => buildAddressWrite({ ...VALID, phone: 'call me' }), {
    code: 'INVALID_ADDRESS_PHONE'
  });
  // The optional second number is held to the same rule when present.
  assert.throws(() => buildAddressWrite({ ...VALID, altPhone: 'x' }), {
    code: 'INVALID_ADDRESS_PHONE'
  });
  assert.equal(buildAddressWrite({ ...VALID, altPhone: '' }).altPhone, '');
});

test('a city must belong to the governorate it was sent with', () => {
  assert.throws(
    () => buildAddressWrite({ ...VALID, governorate: 'أريحا', city: 'جنين' }),
    { code: 'INVALID_ADDRESS_CITY' }
  );
});

test('an unserved governorate is refused', () => {
  assert.throws(() => buildAddressWrite({ ...VALID, governorate: 'باريس' }), {
    code: 'INVALID_ADDRESS_GOVERNORATE'
  });
});

test('a closed governorate is refused at the door, not at delivery', () => {
  // The artboard marks these «مغلق». Accepting one and disappointing the
  // customer later is worse than refusing it now.
  assert.throws(
    () =>
      buildAddressWrite({
        ...VALID,
        governorate: 'الناصرة',
        city: 'الناصرة'
      }),
    { code: 'ADDRESS_GOVERNORATE_CLOSED' }
  );
});

test('details are bounded', () => {
  assert.throws(
    () =>
      buildAddressWrite({
        ...VALID,
        details: 'x'.repeat(ADDRESS_LIMITS.detailsMax + 1)
      }),
    { code: 'INVALID_ADDRESS_DETAILS' }
  );
});

test('the label is truncated rather than refused', () => {
  // A long label is a nuisance, not an attack; the address is still good.
  const write = buildAddressWrite({ ...VALID, label: 'ب'.repeat(200) });

  assert.equal(write.label.length, ADDRESS_LIMITS.labelMax);
});

// ---------------------------------------------------------------------------
// Exactly one default.
// ---------------------------------------------------------------------------

const book = (...flags) =>
  flags.map((isDefault, index) => ({
    _id: `id${index}`,
    isDefault
  }));

test('an empty book stays empty', () => {
  assert.deepEqual(normalizeDefaults([]), []);
});

test('the preferred address becomes the only default', () => {
  const addresses = normalizeDefaults(book(true, false, false), 'id2');

  assert.deepEqual(
    addresses.map((entry) => entry.isDefault),
    [false, false, true]
  );
});

test('with nothing preferred the existing default survives', () => {
  const addresses = normalizeDefaults(book(false, true, false));

  assert.deepEqual(
    addresses.map((entry) => entry.isDefault),
    [false, true, false]
  );
});

test('a book with no default gets one', () => {
  // Otherwise checkout sends the customer back to the form every time.
  const addresses = normalizeDefaults(book(false, false));

  assert.deepEqual(
    addresses.map((entry) => entry.isDefault),
    [true, false]
  );
});

test('two claimed defaults collapse to one', () => {
  const addresses = normalizeDefaults(book(true, true, true));

  assert.equal(
    addresses.filter((entry) => entry.isDefault).length,
    1
  );
});

test('a preferred id that is not in the book does not blank the default', () => {
  const addresses = normalizeDefaults(book(false, true), 'gone');

  assert.equal(addresses.filter((entry) => entry.isDefault).length, 1);
});

// ---------------------------------------------------------------------------
// Regions and the order snapshot.
// ---------------------------------------------------------------------------

test('the region list says which governorates are closed', () => {
  const regions = deliveryRegions();

  assert.equal(regions.length > 0, true);
  assert.equal(regions.some((region) => region.open === false), true);
  assert.equal(findRegion('الناصرة').open, false);
  assert.equal(findRegion('أريحا').open, true);
  assert.equal(findRegion('nowhere'), null);
});

test('the region list is a copy, so a caller cannot edit the source', () => {
  const first = deliveryRegions();
  first[0].cities.push('مدينة مخترعة');

  assert.equal(deliveryRegions()[0].cities.includes('مدينة مخترعة'), false);
});

test('an order snapshots the address as one line', () => {
  // Editing or deleting a saved address later must not rewrite where a past
  // order went, so the order stores text rather than a reference.
  assert.equal(
    formatAddressLine({
      governorate: 'أريحا',
      city: 'أريحا',
      details: 'شارع القدس'
    }),
    'أريحا ، أريحا ، شارع القدس'
  );
  assert.equal(
    formatAddressLine({ governorate: 'جنين', city: 'جنين', details: '' }),
    'جنين ، جنين'
  );
});

test('the book is bounded', () => {
  assert.equal(MAX_ADDRESSES > 0, true);
  assert.equal(MAX_ADDRESSES <= 20, true);
});
