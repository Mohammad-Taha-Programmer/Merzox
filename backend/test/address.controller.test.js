import assert from 'node:assert/strict';
import test from 'node:test';

import { User } from '../src/models/User.js';
import {
  createMyAddress,
  deleteMyAddress,
  listDeliveryRegions,
  listMyAddresses,
  setMyDefaultAddress,
  updateMyAddress
} from '../src/controllers/address.controller.js';
import { MAX_ADDRESSES } from '../src/policies/address.policy.js';

/**
 * The address book handlers, driven directly.
 *
 * The book is a subdocument array on the account, so the interesting claims
 * are about a single invariant - exactly one default, always, whatever was
 * added, promoted or deleted - and about the refusals: an id that belongs to
 * someone else must be indistinguishable from one that does not exist.
 *
 * No database. `findById` answers with a real document and `save` is a no-op,
 * which is enough because every mutation happens on the document in memory.
 */

function invoke(handler, req = {}) {
  return new Promise((resolve) => {
    const captured = { status: 200, body: null, error: null };
    const res = {
      status(code) {
        captured.status = code;
        return res;
      },
      json(payload) {
        captured.body = payload;
        resolve(captured);
        return res;
      }
    };

    handler({ body: {}, query: {}, params: {}, ...req }, res, (error) => {
      captured.error = error;
      resolve(captured);
    });
  });
}

function stubOwner(user) {
  const originalFindById = User.findById;
  const originalSave = User.prototype.save;
  const state = { saves: 0 };

  User.findById = async () => user;
  User.prototype.save = async function save() {
    state.saves += 1;
    return this;
  };

  state.restore = () => {
    User.findById = originalFindById;
    User.prototype.save = originalSave;
  };

  return state;
}

function owner() {
  return new User({
    name: 'ياسمين خالد',
    phone: '0592029316',
    userType: 'normal'
  });
}

function addressBody(overrides = {}) {
  return {
    label: 'المنزل',
    fullName: 'ياسمين خالد',
    phone: '0592029316',
    governorate: 'رام الله والبيرة',
    city: 'رام الله',
    details: 'عمارة الياسمين',
    ...overrides
  };
}

/** Adds addresses straight onto the document, bypassing the handler. */
function seed(user, count, defaultIndex = 0) {
  for (let index = 0; index < count; index += 1) {
    user.addresses.push({
      label: `عنوان ${index}`,
      fullName: 'ياسمين خالد',
      phone: '0592029316',
      governorate: 'رام الله والبيرة',
      city: 'رام الله',
      details: '',
      isDefault: index === defaultIndex
    });
  }

  return user.addresses;
}

async function run(handler, user, req = {}) {
  const stub = stubOwner(user);

  try {
    return { ...(await invoke(handler, { user: { _id: user._id }, ...req })), saves: stub.saves };
  } finally {
    stub.restore();
  }
}

// ---------------------------------------------------------------------------
// regions
// ---------------------------------------------------------------------------

test('the served regions are published with their closed ones marked', async () => {
  const result = await invoke(listDeliveryRegions);
  const regions = result.body.data.regions;

  assert.ok(regions.length > 0);

  const closed = regions.filter((region) => !region.open);
  // The design lists these and marks them «مغلق» rather than hiding them.
  assert.deepEqual(
    closed.map((region) => region.governorate).sort(),
    ['الجولان', 'الناصرة', 'عكا']
  );

  const ramallah = regions.find((r) => r.governorate === 'رام الله والبيرة');
  assert.ok(ramallah.cities.includes('رام الله'));
});

// ---------------------------------------------------------------------------
// create
// ---------------------------------------------------------------------------

test('the first address is the default whether or not it asked', async () => {
  const user = owner();
  const result = await run(createMyAddress, user, { body: addressBody() });

  assert.equal(result.error, null);
  assert.equal(result.status, 201);
  assert.equal(result.body.data.addresses.length, 1);
  // A book with no default sends the customer back to the form every checkout.
  assert.equal(result.body.data.addresses[0].isDefault, true);
  assert.equal(result.saves, 1);
});

test('a later address claiming the default demotes the one that held it', async () => {
  const user = owner();
  seed(user, 1);

  const result = await run(createMyAddress, user, {
    body: addressBody({ label: 'العمل', isDefault: true })
  });

  const addresses = result.body.data.addresses;
  assert.equal(addresses.length, 2);
  assert.equal(addresses.filter((entry) => entry.isDefault).length, 1);
  assert.equal(addresses.find((entry) => entry.isDefault).label, 'العمل');
});

test('a later address that does not ask leaves the default alone', async () => {
  const user = owner();
  seed(user, 1);

  const result = await run(createMyAddress, user, {
    body: addressBody({ label: 'العمل' })
  });

  const addresses = result.body.data.addresses;
  assert.equal(addresses[0].isDefault, true);
  assert.equal(addresses[1].isDefault, false);
});

test('the book is capped, and the refusal names the cap', async () => {
  const user = owner();
  seed(user, MAX_ADDRESSES);

  const result = await run(createMyAddress, user, { body: addressBody() });

  assert.equal(result.error?.code, 'ADDRESS_LIMIT_REACHED');
  assert.equal(result.error?.statusCode, 409);
  assert.equal(user.addresses.length, MAX_ADDRESSES);
  assert.equal(result.saves, 0);
});

test('a closed governorate is refused at the door, not at delivery', async () => {
  const user = owner();

  const result = await run(createMyAddress, user, {
    body: addressBody({ governorate: 'الناصرة', city: 'الناصرة' })
  });

  assert.equal(result.error?.code, 'ADDRESS_GOVERNORATE_CLOSED');
  assert.equal(user.addresses.length, 0);
});

test('a city that does not belong to its governorate is refused', async () => {
  const user = owner();

  const result = await run(createMyAddress, user, {
    body: addressBody({ governorate: 'أريحا', city: 'رام الله' })
  });

  assert.equal(result.error?.code, 'INVALID_ADDRESS_CITY');
  assert.equal(user.addresses.length, 0);
});

// ---------------------------------------------------------------------------
// addressing someone else's address
// ---------------------------------------------------------------------------

test('an unknown address and one belonging elsewhere read the same', async () => {
  const user = owner();
  seed(user, 1);

  const stranger = owner();
  const strangersAddress = seed(stranger, 1)[0]._id.toString();
  const neverExisted = '64d000000000000000000999';

  for (const addressId of [strangersAddress, neverExisted]) {
    const result = await run(setMyDefaultAddress, user, { params: { addressId } });

    assert.equal(result.error?.code, 'ADDRESS_NOT_FOUND');
    assert.equal(result.error?.statusCode, 404);
  }
});

test('a malformed address id is refused before any lookup', async () => {
  const user = owner();
  seed(user, 1);

  const result = await run(deleteMyAddress, user, {
    params: { addressId: 'not-an-object-id' }
  });

  assert.equal(result.error?.code, 'INVALID_ADDRESS_ID');
  assert.equal(user.addresses.length, 1);
});

// ---------------------------------------------------------------------------
// update, promote, delete
// ---------------------------------------------------------------------------

test('an edit changes the fields it sent and not the default', async () => {
  const user = owner();
  const [first, second] = seed(user, 2);

  const result = await run(updateMyAddress, user, {
    params: { addressId: second._id.toString() },
    body: addressBody({ label: 'الجديد', details: 'الطابق الثالث' })
  });

  const addresses = result.body.data.addresses;
  assert.equal(addresses[1].label, 'الجديد');
  assert.equal(addresses[1].details, 'الطابق الثالث');
  // `isDefault` was not sent, so it was not moved.
  assert.equal(addresses[0].id, first._id.toString());
  assert.equal(addresses[0].isDefault, true);
  assert.equal(addresses[1].isDefault, false);
});

test('an edit that asks for the default takes it', async () => {
  const user = owner();
  const [, second] = seed(user, 2);

  const result = await run(updateMyAddress, user, {
    params: { addressId: second._id.toString() },
    body: addressBody({ isDefault: true })
  });

  const addresses = result.body.data.addresses;
  assert.equal(addresses.filter((entry) => entry.isDefault).length, 1);
  assert.equal(addresses[1].isDefault, true);
});

test('promoting moves the default and nothing else', async () => {
  const user = owner();
  const [, second] = seed(user, 2);
  const labelBefore = second.label;

  const result = await run(setMyDefaultAddress, user, {
    params: { addressId: second._id.toString() }
  });

  const addresses = result.body.data.addresses;
  assert.equal(addresses[1].isDefault, true);
  assert.equal(addresses[0].isDefault, false);
  assert.equal(addresses[1].label, labelBefore);
});

test('deleting the default promotes another rather than leaving none', async () => {
  const user = owner();
  const [first] = seed(user, 3);

  const result = await run(deleteMyAddress, user, {
    params: { addressId: first._id.toString() }
  });

  const addresses = result.body.data.addresses;
  assert.equal(addresses.length, 2);
  assert.equal(addresses.filter((entry) => entry.isDefault).length, 1);
});

test('deleting the last address leaves an empty book, not a broken one', async () => {
  const user = owner();
  const [only] = seed(user, 1);

  const result = await run(deleteMyAddress, user, {
    params: { addressId: only._id.toString() }
  });

  assert.equal(result.error, null);
  assert.deepEqual(result.body.data.addresses, []);
});

// ---------------------------------------------------------------------------
// what the list says
// ---------------------------------------------------------------------------

test('the list publishes the address fields and nothing about the account', async () => {
  const user = owner();
  seed(user, 1);

  const result = await run(listMyAddresses, user);
  const [address] = result.body.data.addresses;

  assert.deepEqual(Object.keys(address).sort(), [
    'altPhone',
    'city',
    'details',
    'fullName',
    'governorate',
    'id',
    'isDefault',
    'label',
    'phone'
  ]);
  assert.equal(typeof address.id, 'string');
  assert.equal(Object.keys(result.body.data).length, 1);
});
