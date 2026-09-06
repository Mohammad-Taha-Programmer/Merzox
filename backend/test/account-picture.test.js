import assert from 'node:assert/strict';
import test from 'node:test';

import {
  applyLogoToConversations,
  applyPictureToOwnedBusiness
} from '../src/services/account-picture.service.js';

/// One picture, not two.
///
/// A merchant's account picture and their shop's logo were separate fields
/// with no connection, so setting the picture changed the bar the merchant
/// looks at and left the card a customer sees on whatever it had. There was
/// no way to reconcile them from the app at all.

/// Records what it was asked to write, and whether a shop was there to write
/// to. Returns the shop's id, which is what the conversations are reached by.
///
/// A second fake stands in for the conversations that hold a copy of the logo,
/// so neither of them reaches a database.
function fakeConversations() {
  const calls = [];

  return {
    calls,
    async updateMany(filter, update) {
      calls.push({ filter, update });
      return { modifiedCount: calls.length };
    }
  };
}

function fakeBusinesses({ found = true } = {}) {
  const calls = [];

  return {
    calls,
    async findOneAndUpdate(filter, update) {
      calls.push({ filter, update });
      return found ? { _id: 'shop-1' } : null;
    }
  };
}

test('the shop a merchant owns takes the picture as its logo', async () => {
  const model = fakeBusinesses();

  const applied = await applyPictureToOwnedBusiness('owner-1', 'https://res.cloudinary.com/x/pic.png', {
    model,
    conversations: fakeConversations()
  });

  assert.equal(applied, true);
  assert.equal(model.calls.length, 1);
  assert.deepEqual(model.calls[0].filter, { owner: 'owner-1' });
  assert.deepEqual(model.calls[0].update, {
    $set: { logoUrl: 'https://res.cloudinary.com/x/pic.png' }
  });
});

test('it is addressed by ownership, never by a shop id from the client', async () => {
  const model = fakeBusinesses();
  await applyPictureToOwnedBusiness('owner-1', 'https://x/y.png', {
    model,
    conversations: fakeConversations()
  });

  // The only thing that decides which shop is touched is who is signed in.
  assert.deepEqual(Object.keys(model.calls[0].filter), ['owner']);
});

test('nothing but the logo is written', async () => {
  const model = fakeBusinesses();
  await applyPictureToOwnedBusiness('owner-1', 'https://x/y.png', {
    model,
    conversations: fakeConversations()
  });

  const update = model.calls[0].update;
  assert.deepEqual(Object.keys(update), ['$set']);
  assert.deepEqual(Object.keys(update.$set), ['logoUrl']);
});

test('a customer owns no shop, and that is not a failure', async () => {
  const model = fakeBusinesses({ found: false });

  // Every account can set a picture. Only some of them own a shop, and the
  // ones that do not must not be refused.
  assert.equal(
    await applyPictureToOwnedBusiness('customer-1', 'https://x/y.png', {
    model,
    conversations: fakeConversations()
  }),
    false
  );
  assert.equal(model.calls.length, 1);
});

test('a disabled shop still takes it', async () => {
  const model = fakeBusinesses();
  await applyPictureToOwnedBusiness('owner-1', 'https://x/y.png', {
    model,
    conversations: fakeConversations()
  });

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
    assert.equal(await applyPictureToOwnedBusiness(owner, url, {
      model,
      conversations: fakeConversations()
    }), false);
  }

  assert.equal(model.calls.length, 0, 'a blank picture must not clear a logo');
});

test('a conversation is addressed by its shop, and only its logo is written', async () => {
  // The inbox keeps a copy of the logo so it can draw a list without loading
  // every shop behind it, and nothing refreshed that copy - so a merchant who
  // set a picture kept a blank circle in every conversation already open.
  const calls = [];
  const model = {
    async updateMany(filter, update) {
      calls.push({ filter, update });
      return { modifiedCount: 3 };
    }
  };

  const changed = await applyLogoToConversations('shop-1', 'https://x/y.png', {
    model
  });

  assert.equal(changed, 3);
  assert.deepEqual(calls[0].filter, { business: 'shop-1' });
  assert.deepEqual(Object.keys(calls[0].update.$set), ['businessLogoUrl']);
  assert.equal(calls[0].update.$set.businessLogoUrl, 'https://x/y.png');
});

test('a shop with no id is not a query for every conversation there is', async () => {
  const model = fakeConversations();

  assert.equal(
    await applyLogoToConversations(null, 'https://x/y.png', { model }),
    0
  );
  assert.equal(
    await applyLogoToConversations('', 'https://x/y.png', { model }),
    0
  );
  assert.equal(model.calls.length, 0);
});
