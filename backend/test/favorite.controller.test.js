import assert from 'node:assert/strict';
import mongoose from 'mongoose';
import test from 'node:test';

import { Business } from '../src/models/Business.js';
import { Favorite } from '../src/models/Favorite.js';
import {
  getBusinessFavoriteStatus,
  listFavoriteBusinesses,
  listFavoriteProducts,
  setBusinessFavorite
} from '../src/controllers/favorite.controller.js';

/**
 * The favourites handlers, driven directly.
 *
 * A favourite outlives the thing it points at: shops close and products are
 * hidden while the row stays. So the claims worth pinning are about what the
 * handlers do with a dangling favourite, and about the follower count, which
 * is denormalised onto the business and therefore has to be recomputed rather
 * than incremented.
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

    handler(
      { body: {}, query: {}, params: {}, user: { _id: 'user-1' }, ...req },
      res,
      (error) => {
        captured.error = error;
        resolve(captured);
      }
    );
  });
}

/** Stands in for a Mongoose query: chainable, and awaitable at any point. */
function chain(value) {
  const self = {
    sort: () => self,
    skip: () => self,
    limit: () => self,
    populate: () => Promise.resolve(value),
    lean: () => Promise.resolve(value),
    then: (resolve, reject) => Promise.resolve(value).then(resolve, reject)
  };

  return self;
}

function stub({ favorites = [], count = null, businesses = [], one = null } = {}) {
  const originals = {
    find: Favorite.find,
    countDocuments: Favorite.countDocuments,
    updateOne: Favorite.updateOne,
    deleteOne: Favorite.deleteOne,
    businessFind: Business.find,
    businessFindById: Business.findById,
    businessFindOne: Business.findOne,
    businessUpdateOne: Business.updateOne
  };

  const state = {
    upserts: [],
    deletes: [],
    counted: [],
    businessWrites: [],
    lookedUpBy: []
  };

  Favorite.find = (filter) => {
    state.counted.push(filter);
    return chain(favorites);
  };
  Favorite.countDocuments = async (filter) => {
    state.counted.push(filter);
    return count ?? favorites.length;
  };
  Favorite.updateOne = async (filter, update, options) => {
    state.upserts.push({ filter, update, options });
    return { acknowledged: true };
  };
  Favorite.deleteOne = async (filter) => {
    state.deletes.push(filter);
    return { deletedCount: 1 };
  };

  Business.find = async () => businesses;
  Business.findById = async (id) => {
    state.lookedUpBy.push({ by: 'id', value: id });
    return one;
  };
  Business.findOne = async (filter) => {
    state.lookedUpBy.push({ by: 'publicId', value: filter.publicId });
    return one;
  };
  Business.updateOne = async (filter, update) => {
    state.businessWrites.push({ filter, update });
    return { acknowledged: true };
  };

  state.restore = () => {
    Favorite.find = originals.find;
    Favorite.countDocuments = originals.countDocuments;
    Favorite.updateOne = originals.updateOne;
    Favorite.deleteOne = originals.deleteOne;
    Business.find = originals.businessFind;
    Business.findById = originals.businessFindById;
    Business.findOne = originals.businessFindOne;
    Business.updateOne = originals.businessUpdateOne;
  };

  return state;
}

function shop({ name = 'متجر الياسمين', isActive = true, products = [] } = {}) {
  return new Business({
    publicId: 'MXB-TEST-1',
    name,
    category: 'مستحضرات تجميل',
    address: 'رام الله',
    isActive,
    products
  });
}

async function run(handler, stubs, req = {}) {
  const state = stub(stubs);

  try {
    return { ...(await invoke(handler, req)), state };
  } finally {
    state.restore();
  }
}

// ---------------------------------------------------------------------------
// listing
// ---------------------------------------------------------------------------

test('a favourite whose shop has closed is left out of the list', async () => {
  const open = shop();
  const result = await run(listFavoriteBusinesses, {
    favorites: [
      { business: open, createdAt: new Date('2026-01-01') },
      // `populate` matched on isActive, so a closed shop arrives as null.
      { business: null, createdAt: new Date('2026-01-02') }
    ],
    count: 2
  });

  assert.equal(result.body.data.businesses.length, 1);
  assert.equal(result.body.data.businesses[0].name, 'متجر الياسمين');
  assert.ok(result.body.data.businesses[0].favoritedAt);
});

test('the page size is clamped at both ends', async () => {
  const wide = await run(listFavoriteBusinesses, {}, { query: { limit: '5000' } });
  assert.equal(wide.body.data.pagination.limit, 100);

  const narrow = await run(listFavoriteBusinesses, {}, { query: { limit: '0' } });
  assert.equal(narrow.body.data.pagination.limit, 1);

  const backwards = await run(listFavoriteBusinesses, {}, { query: { page: '-3' } });
  assert.equal(backwards.body.data.pagination.page, 1);
});

test('the list is scoped to the caller and to one kind of favourite', async () => {
  const result = await run(listFavoriteBusinesses, {});

  assert.deepEqual(result.state.counted[0], {
    user: 'user-1',
    itemType: 'business'
  });
});

test('a favourited product survives only while its shop and it are live', async () => {
  const live = { name: 'أساس فت مي', price: 35, isActive: true };
  const hidden = { name: 'مخفي', price: 10, isActive: false };
  const store = shop({ products: [live, hidden] });
  const [liveProduct, hiddenProduct] = store.products;

  const result = await run(listFavoriteProducts, {
    businesses: [store],
    favorites: [
      { business: store._id, productId: liveProduct._id, createdAt: new Date() },
      { business: store._id, productId: hiddenProduct._id, createdAt: new Date() },
      // A row pointing at a shop that no longer loads at all.
      {
        business: new mongoose.Types.ObjectId(),
        productId: new mongoose.Types.ObjectId(),
        createdAt: new Date()
      }
    ],
    count: 3
  });

  assert.deepEqual(
    result.body.data.products.map((entry) => entry.product.name),
    ['أساس فت مي']
  );
  // The count is what the customer favourited; the list is what is still real.
  assert.equal(result.body.data.pagination.total, 3);
});

// ---------------------------------------------------------------------------
// status
// ---------------------------------------------------------------------------

test('the status separates the shop itself from the products inside it', async () => {
  const store = shop();
  const productId = new mongoose.Types.ObjectId();

  const result = await run(
    getBusinessFavoriteStatus,
    {
      one: store,
      favorites: [
        { itemType: 'business' },
        { itemType: 'product', productId }
      ]
    },
    { params: { businessId: store._id.toString() } }
  );

  assert.equal(result.body.data.businessFavorited, true);
  assert.deepEqual(result.body.data.productIds, [productId.toString()]);
  assert.equal(result.body.data.businessId, store._id.toString());
});

test('a shop is addressable by its id or its public id', async () => {
  const store = shop();

  const byId = await run(
    getBusinessFavoriteStatus,
    { one: store },
    { params: { businessId: store._id.toString() } }
  );
  const byPublicId = await run(
    getBusinessFavoriteStatus,
    { one: store },
    { params: { businessId: 'MXB-TEST-1' } }
  );

  assert.equal(byId.state.lookedUpBy[0].by, 'id');
  assert.equal(byPublicId.state.lookedUpBy[0].by, 'publicId');
  assert.equal(byPublicId.error, null);
});

test('a closed shop is not found rather than reported as closed', async () => {
  const result = await run(
    getBusinessFavoriteStatus,
    { one: shop({ isActive: false }) },
    { params: { businessId: 'MXB-TEST-1' } }
  );

  assert.equal(result.error?.code, 'BUSINESS_NOT_FOUND');
  assert.equal(result.error?.statusCode, 404);
});

// ---------------------------------------------------------------------------
// following
// ---------------------------------------------------------------------------

test('following upserts once and never duplicates the row', async () => {
  const store = shop();
  const result = await run(
    setBusinessFavorite,
    { one: store, count: 7 },
    { params: { id: store._id.toString() }, body: { favorited: true } }
  );

  assert.equal(result.error, null);
  assert.equal(result.state.upserts.length, 1);
  assert.equal(result.state.upserts[0].options.upsert, true);
  assert.deepEqual(result.state.upserts[0].filter, {
    user: 'user-1',
    itemType: 'business',
    business: store._id
  });
  assert.equal(result.state.deletes.length, 0);
});

test('unfollowing deletes the row instead of writing a false one', async () => {
  const store = shop();
  const result = await run(
    setBusinessFavorite,
    { one: store, count: 0 },
    { params: { id: store._id.toString() }, body: { favorited: false } }
  );

  assert.equal(result.state.deletes.length, 1);
  assert.equal(result.state.upserts.length, 0);
  assert.equal(result.body.data.favorited, false);
});

test('the follower count is recounted and written back, not incremented', async () => {
  const store = shop();
  store.followerCount = 999;

  const result = await run(
    setBusinessFavorite,
    { one: store, count: 7 },
    { params: { id: store._id.toString() }, body: { favorited: true } }
  );

  // A denormalised counter that is incremented drifts; this one is recomputed
  // from the rows every time it changes.
  assert.deepEqual(result.state.businessWrites[0].update, {
    $set: { followerCount: 7 }
  });
  assert.equal(result.body.data.business.followerCount, 7);
});

test('only a real boolean may follow or unfollow', async () => {
  const store = shop();

  for (const favorited of ['true', 1, 0, null, undefined, 'false']) {
    const result = await run(
      setBusinessFavorite,
      { one: store },
      { params: { id: store._id.toString() }, body: { favorited } }
    );

    assert.equal(
      result.error?.code,
      'INVALID_FAVORITE_VALUE',
      `${JSON.stringify(favorited)} must not be read as a choice`
    );
    assert.equal(result.state.upserts.length, 0);
    assert.equal(result.state.deletes.length, 0);
  }
});

test('a closed shop cannot be followed', async () => {
  const result = await run(
    setBusinessFavorite,
    { one: shop({ isActive: false }) },
    { params: { id: 'MXB-TEST-1' }, body: { favorited: true } }
  );

  assert.equal(result.error?.code, 'BUSINESS_NOT_FOUND');
  assert.equal(result.state.upserts.length, 0);
});
