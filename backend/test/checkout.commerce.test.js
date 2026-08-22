import assert from 'node:assert/strict';
import test from 'node:test';

import mongoose from 'mongoose';

import { Business } from '../src/models/Business.js';
import { Order } from '../src/models/Order.js';
import { validateOrderCreate } from '../src/middleware/validate.js';
import {
  CHECKOUT_ERRORS,
  buildStockRelease,
  buildStockReservation,
  deliveryFeeFor,
  isFiniteStockProduct,
  normalizeRequestedItems,
  resolveOrderLines,
  subtotalFor,
  totalFor
} from '../src/policies/checkout.policy.js';
import { isProductInStock } from '../src/policies/product.policy.js';

/**
 * MERZOX-GAP-002 checkout commerce truth.
 *
 * Two claims are under test: the payable price is derived on the server from
 * the stored base price and discount, and finite inventory cannot be oversold.
 *
 * The reservation is a Mongo filter/update pair rather than a call, so it is
 * exercised here through `applyConditionalUpdate` below - a deliberately small
 * evaluator of the exact operators this policy emits. That proves the QUERY
 * SHAPE is all-or-nothing. It does not prove the driver behaves as documented;
 * the guarded integration suite does that against a real database.
 */

// ------------------------------------------------------------------ fixtures

function productId() {
  return new mongoose.Types.ObjectId();
}

function businessWith(products) {
  return new Business({
    _id: new mongoose.Types.ObjectId(),
    owner: new mongoose.Types.ObjectId(),
    publicId: 'MXB-GAP002-0001',
    name: 'متجر الاختبار',
    category: 'مكياج',
    products
  });
}

/** A finite-stock product. `unlimitedStock: false` is what makes it finite. */
function finiteProduct({ price = 100, discountPercent = 0, stock = 5, isActive = true }) {
  return {
    _id: productId(),
    name: 'منتج محدود',
    price,
    discountPercent,
    unlimitedStock: false,
    stockQuantity: stock,
    isActive
  };
}

function unlimitedProduct({ price = 40, discountPercent = 0, isActive = true }) {
  return {
    _id: productId(),
    name: 'خدمة',
    price,
    discountPercent,
    unlimitedStock: true,
    stockQuantity: 0,
    isActive
  };
}

/** A pre-inventory document: neither stock field is present at all. */
function legacyProduct({ price = 25 } = {}) {
  const product = { _id: productId(), name: 'منتج قديم', price, isActive: true };
  return product;
}

function linesFor(business, items) {
  const normalized = normalizeRequestedItems(items);
  assert.equal(normalized.error, undefined, 'fixture items should normalize');

  const resolved = resolveOrderLines({
    products: business.products,
    items: normalized.items
  });
  assert.equal(resolved.error, undefined, 'fixture items should resolve');

  return resolved.lines;
}

function request(product, quantity) {
  return { productId: product._id.toString(), quantity };
}

// ------------------------------------------------- minimal Mongo update model

function sameId(left, right) {
  return String(left) === String(right);
}

function matchesCondition(value, condition) {
  // Checked before the plain-object branch: an ObjectId is an object too.
  if (condition instanceof mongoose.Types.ObjectId) return sameId(value, condition);

  if (condition !== null && typeof condition === 'object' && !Array.isArray(condition)) {
    if ('$gte' in condition) return Number(value) >= Number(condition.$gte);
    throw new Error(`unsupported condition: ${JSON.stringify(condition)}`);
  }

  return value === condition;
}

function matchesElement(element, criteria) {
  return Object.entries(criteria).every(([field, condition]) => {
    const value = field === '_id' ? element._id : element[field];
    return matchesCondition(value, condition);
  });
}

function matchesFilter(document, filter) {
  for (const [key, condition] of Object.entries(filter)) {
    if (key === '$and') {
      if (!condition.every((clause) => matchesFilter(document, clause))) return false;
      continue;
    }
    if (key === 'products') {
      const criteria = condition.$elemMatch;
      if (!document.products.some((entry) => matchesElement(entry, criteria))) {
        return false;
      }
      continue;
    }
    if (!matchesCondition(document[key], condition)) return false;
  }

  return true;
}

/**
 * Applies one conditional document update the way MongoDB documents it: the
 * filter is evaluated first, and if it does not match, NOTHING is written.
 *
 * Only the operators this policy actually emits are supported, and anything
 * else throws rather than silently passing - a test must not "succeed" against
 * a shape this evaluator does not really understand.
 */
function applyConditionalUpdate(document, { filter, update, arrayFilters }) {
  if (!matchesFilter(document, filter)) {
    return { matchedCount: 0, modifiedCount: 0 };
  }
  if (!update) {
    return { matchedCount: 1, modifiedCount: 0 };
  }

  const increments = Object.entries(update.$inc ?? {});
  if (increments.length === 0) throw new Error('unsupported update');

  for (const [path, delta] of increments) {
    const parsed = /^products\.\$\[(\w+)\]\.(\w+)$/.exec(path);
    if (!parsed) throw new Error(`unsupported update path: ${path}`);

    const [, alias, field] = parsed;
    const criteria = arrayFilters.find((entry) =>
      Object.keys(entry).some((key) => key.startsWith(`${alias}.`))
    );
    assert.ok(criteria, `array filter for ${alias} is missing`);

    const stripped = Object.fromEntries(
      Object.entries(criteria).map(([key, condition]) => [
        key.slice(alias.length + 1),
        condition
      ])
    );

    for (const element of document.products) {
      if (matchesElement(element, stripped)) {
        element[field] = Number(element[field] ?? 0) + delta;
      }
    }
  }

  return { matchedCount: 1, modifiedCount: 1 };
}

function stockOf(business, product) {
  const stored = business.products.find((entry) => sameId(entry._id, product._id));
  return stored.stockQuantity;
}

// ------------------------------------------------------------------- pricing

test('B01 - a discounted product is ordered at the server-derived final price', () => {
  const discounted = finiteProduct({ price: 100, discountPercent: 25, stock: 10 });
  const business = businessWith([discounted]);

  const [line] = linesFor(business, [request(discounted, 2)]);

  assert.equal(line.unitPrice, 75);
  // The base price is NOT what the customer pays.
  assert.notEqual(line.unitPrice, discounted.price);
  // And it is the very number the public serializer already advertises.
  assert.equal(business.productToJSON(discounted).finalPrice, line.unitPrice);
});

test('B02 - the subtotal is built from sale prices, not base prices', () => {
  const discounted = finiteProduct({ price: 100, discountPercent: 25, stock: 10 });
  const plain = unlimitedProduct({ price: 40 });
  const business = businessWith([discounted, plain]);

  const lines = linesFor(business, [request(discounted, 2), request(plain, 1)]);

  // 75*2 + 40*1, not 100*2 + 40.
  assert.equal(subtotalFor(lines), 190);
});

test('B03 - the total derives from the authoritative subtotal plus delivery', () => {
  const discounted = finiteProduct({ price: 35, discountPercent: 15, stock: 4 });
  const business = businessWith([discounted]);

  const subtotal = subtotalFor(linesFor(business, [request(discounted, 2)]));

  assert.equal(subtotal, 59.5);
  assert.equal(deliveryFeeFor(subtotal), 10);
  assert.equal(totalFor(subtotal), 69.5);

  // A basket that is payable-free carries no delivery charge of its own.
  assert.equal(deliveryFeeFor(0), 0);
  assert.equal(totalFor(0), 0);
});

test('B04 - a client cannot supply a price of its own', () => {
  const product = finiteProduct({ price: 100, discountPercent: 50, stock: 5 });
  const business = businessWith([product]);
  const id = product._id.toString();

  // The validator refuses an item that carries any price-shaped field.
  for (const field of ['unitPrice', 'price', 'finalPrice', 'total']) {
    assert.throws(
      () =>
        validateOrderCreate(
          {
            body: {
              businessId: new mongoose.Types.ObjectId().toString(),
              items: [{ productId: id, quantity: 1, [field]: 1 }]
            }
          },
          undefined,
          () => assert.fail('expected rejection')
        ),
      (error) => error.statusCode === 400,
      field
    );
  }

  // And even if one reached the policy, it is never read: the line price comes
  // from the stored product.
  const resolved = resolveOrderLines({
    products: business.products,
    items: [{ productId: id, quantity: 1, unitPrice: 1, price: 1 }]
  });
  assert.equal(resolved.lines[0].unitPrice, 50);
});

// --------------------------------------------------------------------- stock

test('B05 - a finite product with zero stock is refused', () => {
  const product = finiteProduct({ stock: 0 });
  const business = businessWith([product]);

  const resolved = resolveOrderLines({
    products: business.products,
    items: [{ productId: product._id.toString(), quantity: 1 }]
  });

  assert.equal(resolved.error, CHECKOUT_ERRORS.outOfStock);
  assert.equal(resolved.lines, undefined);
});

test('B06 - more than the remaining finite stock is refused', () => {
  const product = finiteProduct({ stock: 3 });
  const business = businessWith([product]);

  const resolved = resolveOrderLines({
    products: business.products,
    items: [{ productId: product._id.toString(), quantity: 4 }]
  });

  assert.equal(resolved.error, CHECKOUT_ERRORS.insufficientStock);
  // The response must not disclose how many units actually remain.
  assert.equal(Object.hasOwn(resolved, 'available'), false);
  assert.equal(Object.hasOwn(resolved, 'stockQuantity'), false);
});

test('B07 - exactly the remaining finite stock is accepted', () => {
  const product = finiteProduct({ stock: 3 });
  const business = businessWith([product]);

  const [line] = linesFor(business, [request(product, 3)]);

  assert.equal(line.quantity, 3);
  assert.equal(line.finite, true);
});

test('B08 - a successful finite purchase consumes exactly the ordered amount', () => {
  const product = finiteProduct({ stock: 5 });
  const business = businessWith([product]);
  const lines = linesFor(business, [request(product, 2)]);

  const result = applyConditionalUpdate(
    business,
    buildStockReservation({ businessId: business._id, lines })
  );

  assert.equal(result.matchedCount, 1);
  assert.equal(stockOf(business, product), 3);
});

test('B09 - stock reaching zero flips the public availability flag', () => {
  const product = finiteProduct({ stock: 2 });
  const business = businessWith([product]);
  const lines = linesFor(business, [request(product, 2)]);

  assert.equal(business.productToJSON(product).inStock, true);

  applyConditionalUpdate(
    business,
    buildStockReservation({ businessId: business._id, lines })
  );

  const stored = business.products.find((entry) => sameId(entry._id, product._id));
  assert.equal(stockOf(business, product), 0);
  assert.equal(isProductInStock(stored), false);
  assert.equal(business.productToJSON(stored).inStock, false);
});

test('B10 - unlimited stock is never decremented', () => {
  const unlimited = unlimitedProduct({});
  const legacy = legacyProduct();
  const business = businessWith([unlimited, legacy]);

  const lines = linesFor(business, [request(unlimited, 9), request(legacy, 7)]);
  assert.equal(lines.every((line) => line.finite === false), true);

  const reservation = buildStockReservation({ businessId: business._id, lines });
  // Nothing to consume at all: no $inc is even produced.
  assert.equal(reservation.update, null);

  const result = applyConditionalUpdate(business, reservation);
  assert.equal(result.matchedCount, 1);
  assert.equal(stockOf(business, unlimited), 0);
  assert.equal(isFiniteStockProduct(legacy), false);
});

test('B11 - an inactive product is refused', () => {
  const product = finiteProduct({ stock: 5, isActive: false });
  const business = businessWith([product]);

  const resolved = resolveOrderLines({
    products: business.products,
    items: [{ productId: product._id.toString(), quantity: 1 }]
  });

  assert.equal(resolved.error, CHECKOUT_ERRORS.notAvailable);
});

// ---------------------------------------------------------------- duplicates

test('B12 - duplicate product ids cannot bypass inventory accounting', () => {
  const product = finiteProduct({ stock: 3 });
  const id = product._id.toString();
  const business = businessWith([product]);

  // Two lines of 2 are one request for 4, which the stock cannot cover.
  const normalized = normalizeRequestedItems([
    { productId: id, quantity: 2 },
    { productId: id, quantity: 2 }
  ]);
  assert.deepEqual(normalized.items, [{ productId: id, quantity: 4 }]);

  const resolved = resolveOrderLines({
    products: business.products,
    items: normalized.items
  });
  assert.equal(resolved.error, CHECKOUT_ERRORS.insufficientStock);

  // Merged within stock: one line, one decrement of the summed quantity.
  const affordable = normalizeRequestedItems([
    { productId: id, quantity: 1 },
    { productId: id, quantity: 2 }
  ]);
  const lines = resolveOrderLines({
    products: business.products,
    items: affordable.items
  }).lines;
  assert.equal(lines.length, 1);

  applyConditionalUpdate(
    business,
    buildStockReservation({ businessId: business._id, lines })
  );
  assert.equal(stockOf(business, product), 0);
});

test('B12 - a merged quantity cannot exceed the per-item bound', () => {
  const id = new mongoose.Types.ObjectId().toString();

  const normalized = normalizeRequestedItems([
    { productId: id, quantity: 60 },
    { productId: id, quantity: 60 }
  ]);

  assert.equal(normalized.error, CHECKOUT_ERRORS.duplicateQuantity);
  assert.equal(normalized.items, undefined);
});

// --------------------------------------------------------------- concurrency

test('B13 - two checkouts for the final unit cannot both succeed', () => {
  const product = finiteProduct({ stock: 1 });
  const business = businessWith([product]);

  // Both requests are resolved against the SAME pre-update read, which is
  // exactly the interleaving a naive read-check-write would get wrong.
  const first = linesFor(business, [request(product, 1)]);
  const second = linesFor(business, [request(product, 1)]);

  const firstResult = applyConditionalUpdate(
    business,
    buildStockReservation({ businessId: business._id, lines: first })
  );
  const secondResult = applyConditionalUpdate(
    business,
    buildStockReservation({ businessId: business._id, lines: second })
  );

  assert.equal(firstResult.matchedCount, 1);
  assert.equal(secondResult.matchedCount, 0, 'the second checkout must not match');
  assert.equal(stockOf(business, product), 0);
});

test('B14 - one unavailable line consumes nothing from the others', () => {
  const affordable = finiteProduct({ stock: 10 });
  const scarce = finiteProduct({ stock: 1 });
  const business = businessWith([affordable, scarce]);

  // Resolve while both look fine, then let the scarce one sell out underneath.
  const lines = linesFor(business, [request(affordable, 2), request(scarce, 1)]);
  business.products.find((entry) => sameId(entry._id, scarce._id)).stockQuantity = 0;

  const result = applyConditionalUpdate(
    business,
    buildStockReservation({ businessId: business._id, lines })
  );

  assert.equal(result.matchedCount, 0);
  assert.equal(stockOf(business, affordable), 10, 'the other item must be untouched');
  assert.equal(stockOf(business, scarce), 0);
});

test('B15 - a released reservation restores the exact quantities', () => {
  const finite = finiteProduct({ stock: 5 });
  const unlimited = unlimitedProduct({});
  const business = businessWith([finite, unlimited]);
  const lines = linesFor(business, [request(finite, 3), request(unlimited, 4)]);

  applyConditionalUpdate(
    business,
    buildStockReservation({ businessId: business._id, lines })
  );
  assert.equal(stockOf(business, finite), 2);

  applyConditionalUpdate(
    business,
    buildStockRelease({ businessId: business._id, lines })
  );

  assert.equal(stockOf(business, finite), 5, 'stock must be given back exactly');
  assert.equal(stockOf(business, unlimited), 0, 'unlimited stock is never invented');
});

test('B16 - a reserve-then-release retry leaves stock consumed only once', () => {
  const product = finiteProduct({ stock: 4 });
  const business = businessWith([product]);
  const lines = linesFor(business, [request(product, 1)]);
  const reservation = buildStockReservation({ businessId: business._id, lines });
  const release = buildStockRelease({ businessId: business._id, lines });

  // First attempt succeeds and keeps its unit.
  applyConditionalUpdate(business, reservation);
  assert.equal(stockOf(business, product), 3);

  // The retry reserves, loses the unique {user, clientOrderId} race, and gives
  // its reservation straight back - which is what the controller does on E11000.
  applyConditionalUpdate(business, reservation);
  assert.equal(stockOf(business, product), 2);
  applyConditionalUpdate(business, release);

  assert.equal(stockOf(business, product), 3, 'a duplicate must not consume stock');
});

test('B17 - the idempotency index makes a duplicate clientOrderId impossible', () => {
  const indexes = Order.schema.indexes();
  const idempotency = indexes.find(
    ([fields]) => fields.user === 1 && fields.clientOrderId === 1
  );

  assert.ok(idempotency, 'expected a {user, clientOrderId} index');
  assert.equal(idempotency[1].unique, true);
  // Partial, so orders without a client id are not forced to collide on null.
  assert.deepEqual(idempotency[1].partialFilterExpression, {
    clientOrderId: { $type: 'string' }
  });
});

// ------------------------------------------------------------------ snapshot

test('B18 - a stored order keeps its purchase-time price', () => {
  const product = finiteProduct({ price: 100, discountPercent: 25, stock: 5 });
  const business = businessWith([product]);
  const [line] = linesFor(business, [request(product, 1)]);

  const order = new Order({
    user: new mongoose.Types.ObjectId(),
    customerName: 'زبون',
    customerPhone: '0590000000',
    business: business._id,
    businessName: business.name,
    businessAddress: 'عنوان',
    items: [
      {
        productId: line.product._id,
        name: line.product.name,
        unitPrice: line.unitPrice,
        quantity: line.quantity
      }
    ],
    subtotal: subtotalFor([line]),
    deliveryFee: deliveryFeeFor(subtotalFor([line])),
    total: totalFor(subtotalFor([line])),
    deliveryAddress: 'عنوان التوصيل'
  });

  assert.equal(order.items[0].unitPrice, 75);

  // The merchant repriced afterwards; the order must not follow.
  const stored = business.products.find((entry) => sameId(entry._id, product._id));
  stored.price = 500;
  stored.discountPercent = 0;

  assert.equal(business.productToJSON(stored).finalPrice, 500);
  assert.equal(order.items[0].unitPrice, 75);
  assert.equal(order.total, 85);
});

// -------------------------------------------------------- merchant privacy

test('B19/B20/B21 - the public serializer still omits merchant-private fields', () => {
  const product = finiteProduct({ price: 100, discountPercent: 25, stock: 7 });
  product.costPrice = 41.25;
  product.keywords = ['private-merchant-keyword'];
  const business = businessWith([product]);

  const stored = business.products.find((entry) => sameId(entry._id, product._id));
  const publicJson = business.productToJSON(stored);
  const ownerJson = business.productToOwnerJSON(stored);

  for (const field of ['costPrice', 'stockQuantity', 'unlimitedStock', 'keywords']) {
    assert.equal(
      Object.hasOwn(publicJson, field),
      false,
      `public product must not expose ${field}`
    );
  }

  // What the customer IS allowed to know about commerce.
  assert.equal(publicJson.discountPercent, 25);
  assert.equal(publicJson.finalPrice, 75);
  assert.equal(publicJson.inStock, true);

  // The owner view still carries the private figures for its own surfaces.
  assert.equal(ownerJson.costPrice, 41.25);
  assert.equal(ownerJson.stockQuantity, 7);
  assert.deepEqual(ownerJson.keywords, ['private-merchant-keyword']);
});
