import assert from 'node:assert/strict';
import test from 'node:test';

import { applyPictureToOwnedBusiness } from '../src/services/account-picture.service.js';

/// One picture, not two.
///
/// A merchant's account picture and their shop's logo were separate fields
/// with no connection, so setting the picture changed the bar the merchant
/// looks at and left the card a customer sees on whatever it had. There was
/// no way to reconcile them from the app at all.

/// Records what it was asked to write, and reports how many shops matched.
function fakeBusinesses({ matchedCount = 1 } = {}) {
  const calls = [];

  return {
    calls,
    async updateOne(filter, update) {
      calls.push({ filter, update });
      return { matchedCount, modifiedCount: matchedCount };
    }
  };
}

test('the shop a merchant owns takes the picture as its logo', async () => {
  const model = fakeBusinesses();

  const applied = await applyPictureToOwnedBusiness(
    'owner-1',
    'https://res.cloudinary.com/x/pic.png',
    { model }
  );

  assert.equal(applied, true);
  assert.deepEqual(model.calls, [
    {
      filter: { owner: 'owner-1' },
      update: { $set: { logoUrl: 'https://res.cloudinary.com/x/pic.png' } }
    }
  ]);
});

test('it is addressed by ownership, never by a shop id from the client', async () => {
  const model = fakeBusinesses();
  await applyPictureToOwnedBusiness('owner-1', 'https://x/y.png', { model });

  // The only thing that decides which shop is touched is who is signed in.
  assert.deepEqual(Object.keys(model.calls[0].filter), ['owner']);
});

test('nothing but the logo is written', async () => {
  const model = fakeBusinesses();
  await applyPictureToOwnedBusiness('owner-1', 'https://x/y.png', { model });

  const update = model.calls[0].update;
  assert.deepEqual(Object.keys(update), ['$set']);
  assert.deepEqual(Object.keys(update.$set), ['logoUrl']);
});

test('a customer owns no shop, and that is not a failure', async () => {
  const model = fakeBusinesses({ matchedCount: 0 });

  // Every account can set a picture. Only some of them own a shop, and the
  // ones that do not must not be refused.
  assert.equal(
    await applyPictureToOwnedBusiness('customer-1', 'https://x/y.png', { model }),
    false
  );
  assert.equal(model.calls.length, 1);
});

test('a disabled shop still takes it', async () => {
  const model = fakeBusinesses();
  await applyPictureToOwnedBusiness('owner-1', 'https://x/y.png', { model });

  // `isActive` is deliberately absent from the filter: the owner is entitled
  // to change their picture, and refusing here would fail the whole request
  // over a shop the merchant cannot even see.
  assert.equal('isActive' in model.calls[0].filter, false);
});

test('nothing to carry means nothing is written', async () => {
  const model = fakeBusinesses();

  for (const [owner, url] of [
    [null, 'https://x/y.png'],
    ['owner-1', ''],
    [undefined, undefined]
  ]) {
    assert.equal(await applyPictureToOwnedBusiness(owner, url, { model }), false);
  }

  assert.equal(model.calls.length, 0, 'a blank picture must not clear a logo');
});
