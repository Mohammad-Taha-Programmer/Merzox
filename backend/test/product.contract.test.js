import assert from 'node:assert/strict';
import test from 'node:test';

import mongoose from 'mongoose';

import { Business } from '../src/models/Business.js';
import {
  validateBusinessProductCreate,
  validateBusinessProductPatch
} from '../src/middleware/validate.js';
import {
  buildProductWrite,
  finalPriceFor,
  isProductInStock,
  LEGACY_UNLIMITED_STOCK_DEFAULT,
  merchantWritableProductFields,
  normalizeKeywords,
  normalizeStock
} from '../src/policies/product.policy.js';

/**
 * FIX4 product contract.
 *
 * The two things these tests protect are: a merchant cannot write a field the
 * contract does not own, and a customer cannot read a field that is
 * merchant-internal.
 */

function accept(validator, body) {
  let called = false;
  validator({ body }, undefined, () => {
    called = true;
  });
  assert.equal(called, true, 'expected next() to be called');
}

function rejectCode(validator, body) {
  try {
    validator({ body }, undefined, () => {
      assert.fail('expected the validator to reject this payload');
    });
  } catch (error) {
    assert.equal(error.statusCode, 400);
    return error.code;
  }
  return assert.fail('expected the validator to throw');
}

const VALID = { name: 'أساس فت مي', price: 35 };

function businessWith(product = {}) {
  return new Business({
    owner: new mongoose.Types.ObjectId(),
    publicId: 'MXB-TEST-0001',
    name: 'متجر الاختبار',
    category: 'مكياج',
    products: [{ name: 'منتج', price: 10, ...product }]
  });
}

// ---------------------------------------------------------------- validation

test('a full valid merchant payload is accepted', () => {
  accept(validateBusinessProductCreate, {
    name: 'أساس فت مي',
    description: 'كريم أساس سائل',
    price: 35,
    costPrice: 20,
    unlimitedStock: false,
    stockQuantity: 12,
    discountPercent: 15,
    keywords: ['مكياج', 'أساس'],
    imageUrls: ['https://example.test/a.png'],
    classification: 'offers',
    isService: false,
    isActive: true
  });
});

test('server-controlled fields cannot be injected', () => {
  for (const field of [
    '_id',
    'id',
    'rating',
    'ratingAverage',
    'ratingCount',
    'likeCount',
    'createdAt',
    'updatedAt',
    'owner',
    'business',
    'finalPrice',
    'inStock'
  ]) {
    assert.equal(
      rejectCode(validateBusinessProductCreate, { ...VALID, [field]: 1 }),
      'INVALID_PRODUCT_FIELDS',
      `${field} must be refused`
    );
    assert.equal(
      merchantWritableProductFields.includes(field),
      false,
      `${field} must not be merchant-writable`
    );
  }
});

test('name and price are validated', () => {
  assert.equal(
    rejectCode(validateBusinessProductCreate, { ...VALID, name: 'x' }),
    'INVALID_PRODUCT_NAME'
  );
  assert.equal(
    rejectCode(validateBusinessProductCreate, { ...VALID, name: 'x'.repeat(121) }),
    'INVALID_PRODUCT_NAME'
  );

  for (const price of [-1, 'abc', NaN, Infinity, null]) {
    assert.equal(
      rejectCode(validateBusinessProductCreate, { ...VALID, price }),
      'INVALID_PRODUCT_PRICE',
      `price ${price}`
    );
  }
});

test('cost price is optional but must be a nonnegative number', () => {
  accept(validateBusinessProductCreate, { ...VALID, costPrice: 0 });
  accept(validateBusinessProductCreate, { ...VALID, costPrice: null });
  accept(validateBusinessProductCreate, { ...VALID, costPrice: '' });

  for (const costPrice of [-1, 'abc', NaN]) {
    assert.equal(
      rejectCode(validateBusinessProductCreate, { ...VALID, costPrice }),
      'INVALID_PRODUCT_COST_PRICE',
      `costPrice ${costPrice}`
    );
  }
});

test('stock must be a whole nonnegative count', () => {
  accept(validateBusinessProductCreate, {
    ...VALID,
    unlimitedStock: false,
    stockQuantity: 0
  });

  for (const stockQuantity of [-1, 1.5, 'abc', NaN]) {
    assert.equal(
      rejectCode(validateBusinessProductCreate, {
        ...VALID,
        unlimitedStock: false,
        stockQuantity
      }),
      'INVALID_PRODUCT_STOCK',
      `stockQuantity ${stockQuantity}`
    );
  }

  assert.equal(
    rejectCode(validateBusinessProductCreate, {
      ...VALID,
      unlimitedStock: 'yes'
    }),
    'INVALID_PRODUCT_STOCK_MODE'
  );
});

test('discount is a bounded percentage', () => {
  accept(validateBusinessProductCreate, { ...VALID, discountPercent: 0 });
  accept(validateBusinessProductCreate, { ...VALID, discountPercent: 100 });

  for (const discountPercent of [-1, 101, 'abc', NaN, '15% OFF TODAY!!!']) {
    assert.equal(
      rejectCode(validateBusinessProductCreate, { ...VALID, discountPercent }),
      'INVALID_PRODUCT_DISCOUNT',
      `discountPercent ${discountPercent}`
    );
  }
});

test('keywords are bounded and must be strings', () => {
  accept(validateBusinessProductCreate, { ...VALID, keywords: [] });
  accept(validateBusinessProductCreate, { ...VALID, keywords: ['مكياج'] });

  assert.equal(
    rejectCode(validateBusinessProductCreate, { ...VALID, keywords: 'مكياج' }),
    'INVALID_PRODUCT_KEYWORDS'
  );
  assert.equal(
    rejectCode(validateBusinessProductCreate, { ...VALID, keywords: [1, 2] }),
    'INVALID_PRODUCT_KEYWORDS'
  );
  assert.equal(
    rejectCode(validateBusinessProductCreate, {
      ...VALID,
      keywords: ['x'.repeat(41)]
    }),
    'INVALID_PRODUCT_KEYWORDS'
  );
  assert.equal(
    rejectCode(validateBusinessProductCreate, {
      ...VALID,
      keywords: Array.from({ length: 21 }, (_, index) => `k${index}`)
    }),
    'INVALID_PRODUCT_KEYWORDS'
  );
});

test('images are bounded and dangerous schemes are refused', () => {
  accept(validateBusinessProductCreate, {
    ...VALID,
    imageUrls: ['https://example.test/a.png', 'http://example.test/b.png']
  });

  for (const url of [
    'javascript:alert(1)',
    'file:///C:/Users/sare/a.png',
    'data:image/png;base64,AAAA',
    'C:\\Users\\sare\\Pictures\\a.png',
    '/storage/emulated/0/DCIM/a.png',
    'not-a-url'
  ]) {
    assert.equal(
      rejectCode(validateBusinessProductCreate, { ...VALID, imageUrls: [url] }),
      'INVALID_PRODUCT_IMAGE_URLS',
      `url ${url}`
    );
  }

  assert.equal(
    rejectCode(validateBusinessProductCreate, {
      ...VALID,
      imageUrls: Array.from({ length: 9 }, () => 'https://example.test/a.png')
    }),
    'INVALID_PRODUCT_IMAGE_URLS'
  );
});

test('classification is restricted to the existing enum', () => {
  for (const classification of ['new', 'bestSelling', 'offers']) {
    accept(validateBusinessProductCreate, { ...VALID, classification });
  }
  assert.equal(
    rejectCode(validateBusinessProductCreate, {
      ...VALID,
      classification: 'featured'
    }),
    'INVALID_PRODUCT_CLASSIFICATION'
  );
});

test('a partial update accepts one field and still refuses unknown ones', () => {
  accept(validateBusinessProductPatch, { price: 20 });
  assert.equal(rejectCode(validateBusinessProductPatch, {}), 'INVALID_PRODUCT_FIELDS');
  assert.equal(
    rejectCode(validateBusinessProductPatch, { ratingCount: 5 }),
    'INVALID_PRODUCT_FIELDS'
  );
});

// ------------------------------------------------------------- normalization

test('unlimited stock stores no quantity and uses no sentinel', () => {
  assert.deepEqual(
    normalizeStock({ unlimitedStock: true, stockQuantity: 99 }),
    { unlimitedStock: true, stockQuantity: 0 }
  );
  assert.deepEqual(
    normalizeStock({ unlimitedStock: false, stockQuantity: 7 }),
    { unlimitedStock: false, stockQuantity: 7 }
  );
  // -1 is never an "unlimited" marker.
  assert.deepEqual(
    normalizeStock({ unlimitedStock: false, stockQuantity: -1 }),
    { unlimitedStock: false, stockQuantity: 0 }
  );
});

test('a partial stock edit keeps the stored counterpart', () => {
  assert.deepEqual(
    normalizeStock({ stockQuantity: 5 }, { unlimitedStock: false, stockQuantity: 1 }),
    { unlimitedStock: false, stockQuantity: 5 }
  );
  assert.deepEqual(
    normalizeStock({ unlimitedStock: false }, { unlimitedStock: true, stockQuantity: 0 }),
    { unlimitedStock: false, stockQuantity: 0 }
  );
});

test('keywords are trimmed, de-blanked and de-duplicated', () => {
  assert.deepEqual(
    normalizeKeywords(['  مكياج ', '', '   ', 'أساس', 'مكياج']),
    ['مكياج', 'أساس']
  );
  assert.deepEqual(normalizeKeywords(['Makeup', 'makeup', 'MAKEUP']), ['Makeup']);
  assert.equal(normalizeKeywords('nope'), null);
  assert.equal(normalizeKeywords([1]), null);
  assert.equal(normalizeKeywords(undefined), undefined);
});

test('the write builder emits only contract fields', () => {
  const write = buildProductWrite({
    name: '  أساس  ',
    price: 35.006,
    costPrice: 20,
    discountPercent: 150,
    keywords: [' مكياج ', 'مكياج'],
    _id: 'injected',
    ratingCount: 99
  });

  assert.equal(write.name, 'أساس');
  assert.equal(write.price, 35.01);
  assert.equal(write.costPrice, 20);
  // Clamped rather than stored as an impossible percentage.
  assert.equal(write.discountPercent, 100);
  assert.deepEqual(write.keywords, ['مكياج']);
  assert.equal('_id' in write, false);
  assert.equal('ratingCount' in write, false);
});

test('an omitted field is not written, so the stored value survives', () => {
  const write = buildProductWrite({ price: 10 });

  assert.deepEqual(Object.keys(write), ['price']);
});

// ------------------------------------------------------------ derived values

test('the final price is derived from the base price and discount', () => {
  assert.equal(finalPriceFor({ price: 100, discountPercent: 0 }), 100);
  assert.equal(finalPriceFor({ price: 100, discountPercent: 25 }), 75);
  assert.equal(finalPriceFor({ price: 35, discountPercent: 15 }), 29.75);
  assert.equal(finalPriceFor({ price: 100, discountPercent: 100 }), 0);
  assert.equal(finalPriceFor({ price: undefined, discountPercent: 10 }), 0);
});

test('stock availability follows the unlimited flag', () => {
  assert.equal(isProductInStock({ unlimitedStock: true, stockQuantity: 0 }), true);
  assert.equal(isProductInStock({ unlimitedStock: false, stockQuantity: 3 }), true);
  assert.equal(isProductInStock({ unlimitedStock: false, stockQuantity: 0 }), false);
  // A legacy document has neither field.
  assert.equal(isProductInStock({}), LEGACY_UNLIMITED_STOCK_DEFAULT);
});

// ------------------------------------------------------------------- privacy

test('the public product JSON never exposes merchant-internal fields', () => {
  const business = businessWith({
    name: 'أساس فت مي',
    price: 35,
    costPrice: 20,
    unlimitedStock: false,
    stockQuantity: 12,
    discountPercent: 15,
    keywords: ['مكياج']
  });
  const product = business.products[0];
  const publicJson = business.productToJSON(product);

  assert.equal('costPrice' in publicJson, false, 'costPrice must never be public');
  assert.equal('stockQuantity' in publicJson, false, 'exact stock is merchant-only');
  assert.equal('keywords' in publicJson, false, 'keywords are merchant-only');
  assert.equal('unlimitedStock' in publicJson, false);

  // What a customer legitimately needs is still there.
  assert.equal(publicJson.price, 35);
  assert.equal(publicJson.discountPercent, 15);
  assert.equal(publicJson.finalPrice, 29.75);
  assert.equal(publicJson.inStock, true);

  // The serialized form carries no trace of the field either.
  assert.equal(JSON.stringify(publicJson).includes('costPrice'), false);
});

test('the owner product JSON exposes the merchant-managed fields', () => {
  const business = businessWith({
    price: 35,
    costPrice: 20,
    unlimitedStock: false,
    stockQuantity: 12,
    discountPercent: 15,
    keywords: ['مكياج']
  });
  const ownerJson = business.productToOwnerJSON(business.products[0]);

  assert.equal(ownerJson.costPrice, 20);
  assert.equal(ownerJson.stockQuantity, 12);
  assert.equal(ownerJson.unlimitedStock, false);
  assert.deepEqual(ownerJson.keywords, ['مكياج']);
  assert.equal(ownerJson.finalPrice, 29.75);
});

test('the business detail payload uses the public product shape', () => {
  const business = businessWith({ costPrice: 20, keywords: ['secret'] });
  const detail = business.toDetailJSON();

  assert.equal(JSON.stringify(detail).includes('costPrice'), false);
  assert.equal(JSON.stringify(detail).includes('secret'), false);
});

test('the owner business payload still hides cost price in its product list', () => {
  // toOwnerJSON spreads toDetailJSON, whose products are the public shape.
  // Merchant product management goes through the dedicated owner endpoints.
  const business = businessWith({ costPrice: 20 });
  const owner = business.toOwnerJSON();

  assert.equal(JSON.stringify(owner.products).includes('costPrice'), false);
});

// -------------------------------------------------------- legacy compatibility

test('a product stored before FIX4 still serializes safely', () => {
  // Exactly the shape a pre-FIX4 document has: no stock, discount, cost, or
  // keyword fields at all.
  const business = new Business({
    owner: new mongoose.Types.ObjectId(),
    publicId: 'MXB-LEGACY-0001',
    name: 'متجر قديم',
    category: 'مكياج'
  });
  business.products.push({ name: 'منتج قديم', price: 12 });
  const product = business.products[0];

  const publicJson = business.productToJSON(product);
  const ownerJson = business.productToOwnerJSON(product);

  assert.equal(publicJson.price, 12);
  assert.equal(publicJson.discountPercent, 0);
  assert.equal(publicJson.finalPrice, 12);
  // The critical one: a legacy product must not read as out of stock.
  assert.equal(publicJson.inStock, true);

  assert.equal(ownerJson.costPrice, null);
  assert.equal(ownerJson.unlimitedStock, LEGACY_UNLIMITED_STOCK_DEFAULT);
  assert.deepEqual(ownerJson.keywords, []);
});

test('the schema defaults keep legacy products purchasable', () => {
  const business = businessWith({});
  const product = business.products[0];

  assert.equal(business.validateSync(), undefined);
  assert.equal(product.unlimitedStock, true);
  assert.equal(product.stockQuantity, 0);
  assert.equal(product.discountPercent, 0);
  assert.equal(product.costPrice, null);
  assert.deepEqual([...product.keywords], []);
  assert.equal(isProductInStock(product), true);
});
