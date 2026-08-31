import assert from 'node:assert/strict';
import test from 'node:test';

import { Business } from '../src/models/Business.js';
import { searchCatalog } from '../src/controllers/search.controller.js';

/**
 * The catalog search handler, driven directly.
 *
 * It builds a regular expression out of whatever the customer typed and then
 * runs that expression against every business it loaded, so the claims worth
 * pinning are: the needle is escaped rather than executed, it is bounded, an
 * empty search costs nothing, and the results carry the public projection of a
 * product rather than the merchant's own view of it.
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

/** `Business.find(...).sort(...).limit(...)` resolved from a fixed list. */
function stubBusinesses(list) {
  const originalFind = Business.find;
  const state = { filters: [], limit: null };

  Business.find = (filter) => {
    state.filters.push(filter);
    const chain = {
      sort: () => chain,
      limit(value) {
        state.limit = value;
        return Promise.resolve(list);
      }
    };
    return chain;
  };

  state.restore = () => {
    Business.find = originalFind;
  };

  return state;
}

function business({ name, category = 'مستحضرات تجميل', description = '', products = [] }) {
  return new Business({
    publicId: `MXB-${name}`,
    name,
    category,
    description,
    owner: undefined,
    address: 'رام الله',
    products
  });
}

function product(name, overrides = {}) {
  return { name, price: 35, isActive: true, ...overrides };
}

async function search(list, query) {
  const stub = stubBusinesses(list);

  try {
    return { ...(await invoke(searchCatalog, { query })), filters: stub.filters, limit: stub.limit };
  } finally {
    stub.restore();
  }
}

test('an empty search asks the database for nothing', async () => {
  for (const query of [{}, { q: '' }, { query: '   ' }]) {
    const result = await search([business({ name: 'متجر' })], query);

    assert.equal(result.error, null);
    assert.deepEqual(result.body.data, { query: '', products: [], businesses: [] });
    // The handler returns before building a pattern or issuing a query.
    assert.deepEqual(result.filters, []);
  }
});

test('the needle is escaped, so it is matched and never executed', async () => {
  const shop = business({
    name: 'متجر الياسمين',
    products: [product('axxb'), product('a.*b')]
  });

  const result = await search([shop], { q: 'a.*b' });
  const names = result.body.data.products.map((entry) => entry.name);

  // An unescaped needle would have swallowed `axxb` as well.
  assert.deepEqual(names, ['a.*b']);
});

test('the needle is bounded before it reaches the pattern', async () => {
  const result = await search([business({ name: 'متجر' })], {
    q: 'x'.repeat(500)
  });

  assert.equal(result.body.data.query.length, 80);
});

test('a hidden product is not found even when its shop matches', async () => {
  const shop = business({
    name: 'متجر الياسمين',
    products: [product('أساس فت مي'), product('مخفي', { isActive: false })]
  });

  const result = await search([shop], { q: 'الياسمين' });
  const names = result.body.data.products.map((entry) => entry.name);

  assert.deepEqual(names, ['أساس فت مي']);
  assert.equal(result.body.data.businesses.length, 1);
});

test('a shop matched by name contributes the products it still sells', async () => {
  const matching = business({
    name: 'متجر الياسمين',
    products: [product('أساس'), product('ماسكارا')]
  });
  const other = business({ name: 'متاجر الشرق', products: [product('عطر')] });

  const result = await search([matching, other], { q: 'الياسمين' });

  assert.deepEqual(
    result.body.data.products.map((entry) => entry.name),
    ['أساس', 'ماسكارا']
  );
  assert.deepEqual(
    result.body.data.businesses.map((entry) => entry.name),
    ['متجر الياسمين']
  );
});

test('a shop is returned when only one of its products matches', async () => {
  const shop = business({
    name: 'متاجر الشرق',
    products: [product('ماسكارا'), product('عطر')]
  });

  const result = await search([shop], { q: 'عطر' });

  assert.deepEqual(
    result.body.data.products.map((entry) => entry.name),
    ['عطر']
  );
  assert.equal(result.body.data.businesses.length, 1);
});

test('a product result carries the public projection, not the merchant view', async () => {
  const shop = business({
    name: 'متجر الياسمين',
    products: [product('أساس', { costPrice: 20, stockQuantity: 40, discountPercent: 50 })]
  });

  const result = await search([shop], { q: 'أساس' });
  const [entry] = result.body.data.products;

  // Margin data is merchant-internal and must not ride along on a search.
  assert.equal(Object.prototype.hasOwnProperty.call(entry, 'costPrice'), false);
  assert.equal(Object.prototype.hasOwnProperty.call(entry, 'stockQuantity'), false);
  // The displayed price is derived from the stored base and discount.
  assert.equal(entry.price, 35);
  assert.equal(entry.finalPrice, 17.5);
  assert.equal(entry.business.name, 'متجر الياسمين');
});

test('the caller may not widen the result set past the cap', async () => {
  const shop = business({
    name: 'متجر',
    products: Array.from({ length: 80 }, (_unused, index) => product(`منتج ${index}`))
  });

  const wide = await search([shop], { q: 'منتج', limit: '999' });
  assert.equal(wide.body.data.products.length, 50);

  const narrow = await search([shop], { q: 'منتج', limit: '2' });
  assert.equal(narrow.body.data.products.length, 2);

  const nonsense = await search([shop], { q: 'منتج', limit: '-5' });
  assert.equal(nonsense.body.data.products.length, 1);
});

test('the search only ever loads shops that are open', async () => {
  const result = await search([business({ name: 'متجر' })], { q: 'متجر' });

  assert.equal(result.filters[0].isActive, true);
});
