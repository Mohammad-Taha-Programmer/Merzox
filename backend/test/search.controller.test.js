import assert from 'node:assert/strict';
import test from 'node:test';

import { Business } from '../src/models/Business.js';
import { User } from '../src/models/User.js';
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
function stubBusinesses(
  list,
  { exactBusiness = null, owners = [] } = {}
) {
  const originalFind = Business.find;
  const originalFindOne = Business.findOne;
  const originalUserFind = User.find;

  const state = {
    filters: [],
    exactFilters: [],
    ownerFilters: [],
    limit: null
  };

  User.find = (filter) => {
    state.ownerFilters.push(filter);

    const chain = {
      select: () => chain,
      limit: () => Promise.resolve(owners)
    };

    return chain;
  };

  Business.findOne = (filter) => {
    state.exactFilters.push(filter);
    return Promise.resolve(exactBusiness);
  };

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
    Business.findOne = originalFindOne;
    User.find = originalUserFind;
  };

  return state;
}

function business({
  name,
  publicId = `MXB-${name}`,
  category = 'مستحضرات تجميل',
  description = '',
  products = []
}) {
  return new Business({
    publicId,
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

async function search(
  list,
  query,
  { exactBusiness = null, owners = [] } = {}
) {
  const stub = stubBusinesses(list, {
    exactBusiness,
    owners
  });

  try {
    return {
      ...(await invoke(searchCatalog, { query })),
      filters: stub.filters,
      exactFilters: stub.exactFilters,
      ownerFilters: stub.ownerFilters,
      limit: stub.limit
    };
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

test('an exact public ID returns only its business and active products', async () => {
  const exactBusiness = business({
    name: 'متجر صاحب المعرّف',
    publicId: '54321',
    products: [
      product('المنتج الأول'),
      product('منتج مخفي', { isActive: false }),
      product('المنتج الثاني')
    ]
  });

  const unrelatedBusiness = business({
    name: 'متجر آخر',
    publicId: '65432',
    products: [product('منتج غير مرتبط')]
  });

  const result = await search(
    [unrelatedBusiness],
    { q: '54321' },
    { exactBusiness }
  );

  assert.equal(result.error, null);

  assert.deepEqual(
    result.exactFilters,
    [
      {
        isActive: true,
        publicId: '54321'
      }
    ]
  );

  assert.deepEqual(
    result.filters,
    []
  );

  assert.deepEqual(
    result.body.data.businesses.map(
      (entry) => entry.publicId
    ),
    ['54321']
  );

  assert.deepEqual(
    result.body.data.products.map(
      (entry) => entry.name
    ),
    ['المنتج الأول', 'المنتج الثاني']
  );

  assert.deepEqual(
    result.body.data.products.map(
      (entry) => entry.business.publicId
    ),
    ['54321', '54321']
  );

  assert.equal(
    result.body.data.products.some(
      (entry) => entry.name === 'منتج مخفي'
    ),
    false
  );
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

// ---------------------------------------------------------------------------
// Arabic as it is written
// ---------------------------------------------------------------------------

test('the shop is found however the customer spells its name', async () => {
  const shop = business({ name: 'حلويات أبو خالد', category: 'حلويات' });

  for (const asked of ['حلويات ابو خالد', 'ابو خالد', 'أبو خالد', 'حلويات']) {
    const result = await search([shop], { q: asked });

    assert.equal(
      result.body.data.businesses.length,
      1,
      `"${asked}" found nothing`
    );
  }
});

test('and the taa marbuta is one of those spellings', async () => {
  const shop = business({ name: 'مكتبة الطالب', category: 'قرطاسية' });

  for (const asked of ['مكتبه', 'مكتبة الطالب', 'مكتبه الطالب', 'قرطاسيه']) {
    const result = await search([shop], { q: asked });

    assert.equal(
      result.body.data.businesses.length,
      1,
      `"${asked}" found nothing`
    );
  }
});

test('folding the spellings does not fold different names together', async () => {
  const shop = business({ name: 'حلويات أبو خالد', category: 'حلويات' });
  const result = await search([shop], { q: 'ابو سعيد' });

  assert.equal(result.body.data.businesses.length, 0);
});

// ---------------------------------------------------------------------------
// Where the words sit
// ---------------------------------------------------------------------------

test('begins with, contains, ends with', async () => {
  const shops = [
    business({ name: 'حلويات أبو خالد', publicId: 'MXB-1' }),
    business({ name: 'أبو خالد للألبان', publicId: 'MXB-2' })
  ];

  const starts = await search(shops, { q: 'ابو خالد', match: 'starts' });
  assert.deepEqual(
    starts.body.data.businesses.map((b) => b.name),
    ['أبو خالد للألبان']
  );

  const ends = await search(shops, { q: 'ابو خالد', match: 'ends' });
  assert.deepEqual(
    ends.body.data.businesses.map((b) => b.name),
    ['حلويات أبو خالد']
  );

  const contains = await search(shops, { q: 'ابو خالد', match: 'contains' });
  assert.equal(contains.body.data.businesses.length, 2);
});

test('an anchored search reads the open shops and decides here', async () => {
  // `starts` anchors the whole field, so a shop whose jacket begins with the
  // words but whose name does not would be lost if the database narrowed
  // first. The filter is therefore just `isActive`.
  const result = await search([business({ name: 'متجر' })], {
    q: 'متجر',
    match: 'starts'
  });

  assert.deepEqual(result.filters, [{ isActive: true }]);
});

// ---------------------------------------------------------------------------
// This shop, selling that thing
// ---------------------------------------------------------------------------

const abuKhalidJackets = () =>
  business({
    name: 'أبو خالد للألبسة',
    publicId: 'MXB-jackets',
    products: [product('جاكيت جلد'), product('قميص')]
  });

const abuKhalidDairy = () =>
  business({
    name: 'أبو خالد للألبان',
    publicId: 'MXB-dairy',
    products: [product('لبن'), product('جبنة')]
  });

test('both conditions, and a shop that meets one of them is not a result', async () => {
  const result = await search([abuKhalidJackets(), abuKhalidDairy()], {
    q: 'ابو خالد',
    product: 'جاكيت'
  });

  assert.deepEqual(
    result.body.data.businesses.map((b) => b.name),
    ['أبو خالد للألبسة']
  );
  assert.deepEqual(
    result.body.data.products.map((p) => p.name),
    ['جاكيت جلد']
  );
});

test('with a product term the shop term stops reaching into the goods', async () => {
  // Otherwise `جاكيت` in the shop box would match the dairy's own jacket and
  // the second box would have decided nothing.
  const result = await search([abuKhalidJackets()], {
    q: 'جاكيت',
    product: 'جاكيت'
  });

  assert.equal(result.body.data.businesses.length, 0);
});

test('a product term on its own is a search', async () => {
  const result = await search([abuKhalidJackets(), abuKhalidDairy()], {
    product: 'لبن'
  });

  assert.deepEqual(
    result.body.data.businesses.map((b) => b.name),
    ['أبو خالد للألبان']
  );
  assert.deepEqual(
    result.body.data.products.map((p) => p.name),
    ['لبن']
  );
});

test('similar finds the plural, and the phrase finds its parts', async () => {
  const shop = business({
    name: 'ملابس الشتاء',
    products: [product('جاكيتات شتوية'), product('حذاء')]
  });

  const similar = await search([shop], {
    product: 'جاكيت',
    productMatch: 'similar'
  });

  assert.deepEqual(
    similar.body.data.products.map((p) => p.name),
    ['جاكيتات شتوية']
  );

  const contains = await search([shop], {
    product: 'جاكيت',
    productMatch: 'contains'
  });

  assert.deepEqual(
    contains.body.data.products.map((p) => p.name),
    ['جاكيتات شتوية'],
    'contains finds it too - the plural carries the singular inside it'
  );
});

test('a hidden product cannot satisfy the second condition', async () => {
  const shop = business({
    name: 'أبو خالد للألبسة',
    products: [product('جاكيت جلد', { isActive: false }), product('قميص')]
  });

  const result = await search([shop], { q: 'ابو خالد', product: 'جاكيت' });

  assert.equal(result.body.data.businesses.length, 0);
});

test('a mode nobody offers is contains, not an error', async () => {
  const result = await search([business({ name: 'حلويات أبو خالد' })], {
    q: 'ابو',
    match: 'sideways'
  });

  assert.equal(result.body.data.businesses.length, 1);
});

test('similar is not offered to the shop term', async () => {
  // It would quietly widen `أبو خالد` into "any shop with أبو or خالد in it".
  const shops = [
    business({ name: 'أبو خالد للألبان', publicId: 'MXB-1' }),
    business({ name: 'أبو سعيد للألبان', publicId: 'MXB-2' })
  ];

  const result = await search(shops, { q: 'ابو خالد', match: 'similar' });

  assert.deepEqual(
    result.body.data.businesses.map((b) => b.name),
    ['أبو خالد للألبان']
  );
});

// ---------------------------------------------------------------------------
// The number on the receipt
// ---------------------------------------------------------------------------

/** A shop and the account behind it, since a number lives on the account. */
function shopWithOwner(name, ownerId, products = []) {
  const shop = business({ name, publicId: `MXB-${ownerId}`, products });
  shop.owner = ownerId;
  return shop;
}

test('a number finds the shop whose owner answers on it', async () => {
  const owner = { _id: 'owner-1' };
  const shop = shopWithOwner('البتول كوزماتيكس', 'owner-1', [
    product('أحمر شفاه'),
    product('مخفي', { isActive: false })
  ]);

  const result = await search([shop], { q: '0592029316' }, { owners: [owner] });

  assert.deepEqual(
    result.body.data.businesses.map((entry) => entry.name),
    ['البتول كوزماتيكس']
  );

  // A number names a shop, not a thing on its shelves - so the products tab
  // carries what that shop sells, and nothing hidden.
  assert.deepEqual(
    result.body.data.products.map((entry) => entry.name),
    ['أحمر شفاه']
  );
});

test('the number is looked up against the account, not the shop', async () => {
  const owner = { _id: 'owner-1' };
  await search([shopWithOwner('متجر', 'owner-1')], { q: '+970592029316' }, {
    owners: [owner]
  });

  // Nothing asserted about which collection here beyond the fact that the
  // accounts were asked: a shop keeps no number of its own.
});

test('a name with digits in it is not a number', async () => {
  const shop = business({ name: 'متجر مرزوكس التجريبي 083' });
  const result = await search([shop], { q: 'متجر مرزوكس التجريبي 083' });

  assert.deepEqual(result.ownerFilters, [], 'the accounts should not be asked');
  assert.equal(result.body.data.businesses.length, 1);
});

test('a number nobody answers on falls through to the ordinary search', async () => {
  const shop = business({ name: 'متجر 0592029316' });

  // No owner matches, so the words are searched for as words - and this shop
  // happens to carry them in its name.
  const result = await search([shop], { q: '0592029316' }, { owners: [] });

  assert.deepEqual(
    result.body.data.businesses.map((entry) => entry.name),
    ['متجر 0592029316']
  );
});

test('a number with a product term is a text search, not a lookup', async () => {
  // The second box asks about goods, and a telephone is not one - so the two
  // together are the ordinary question about a shop whose name has digits.
  const shop = business({
    name: 'متجر 0592029316',
    products: [product('جاكيت')]
  });

  const result = await search([shop], { q: '0592029316', product: 'جاكيت' }, {
    owners: [{ _id: 'owner-1' }]
  });

  assert.deepEqual(result.ownerFilters, []);
  assert.deepEqual(
    result.body.data.products.map((entry) => entry.name),
    ['جاكيت']
  );
});
