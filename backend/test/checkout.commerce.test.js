import assert from 'node:assert/strict';
import test from 'node:test';

import mongoose from 'mongoose';

import { Business } from '../src/models/Business.js';
import { Order } from '../src/models/Order.js';
import { validateOrderCreate } from '../src/middleware/validate.js';
import {
  buildIdentifiedRelease,
  buildIdentifiedReservation
} from '../src/policies/checkout-intent.policy.js';
import {
  CHECKOUT_ERRORS,
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

    // Explicit rather than merely relying on the schema default, because the
    // conditional-update harness must model the durable Business generation.
    reservationFence: 0,

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

function variantProduct({
  price = 100,
  discountPercent = 0,
  variants = []
} = {}) {
  return {
    _id: productId(),
    name: 'منتج متعدد الخيارات',
    price,
    discountPercent,
    // Parent inventory is deliberately irrelevant while variants exist.
    unlimitedStock: true,
    stockQuantity: 0,
    isActive: true,
    variants: variants.map((variant) => ({
      _id: variant._id ?? productId(),
      label: variant.label,
      priceOverride:
        Object.hasOwn(variant, 'priceOverride')
          ? variant.priceOverride
          : null,
      costPrice: variant.costPrice ?? null,
      unlimitedStock: variant.unlimitedStock ?? false,
      stockQuantity:
        variant.stockQuantity ?? variant.stock ?? 0,
      isActive: variant.isActive ?? true
    }))
  };
}

function variantRequest(product, variant, quantity) {
  return {
    productId: product._id.toString(),
    variantId: variant._id.toString(),
    quantity
  };
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
  if (condition instanceof mongoose.Types.ObjectId) {
    return sameId(value, condition);
  }

  if (
    condition !== null &&
    typeof condition === 'object' &&
    !Array.isArray(condition)
  ) {
    if ('$gte' in condition) {
      return Number(value) >= Number(condition.$gte);
    }

    // Mongo semantics:
    // `$ne` also matches a missing field.
    if ('$ne' in condition) {
      return value !== condition.$ne;
    }

    // Required by the legacy-compatible reservationFence=0 predicate:
    //
    //   reservationFence: { $exists: false }
    //
    // A missing generation is treated as the original generation zero.
    if ('$exists' in condition) {
      return condition.$exists
        ? value !== undefined
        : value === undefined;
    }

    throw new Error(
      `unsupported condition: ${JSON.stringify(condition)}`
    );
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
      if (
        !condition.every((clause) =>
          matchesFilter(document, clause)
        )
      ) {
        return false;
      }

      continue;
    }

    if (key === '$or') {
      if (
        !condition.some((clause) =>
          matchesFilter(document, clause)
        )
      ) {
        return false;
      }

      continue;
    }

    if (key === 'products') {
      const criteria = condition.$elemMatch;
      if (!document.products.some((entry) => matchesElement(entry, criteria))) {
        return false;
      }
      continue;
    }
    // Mongo array-membership semantics: `field: value` matches when the array
    // contains value, and `$ne` matches when it does not. This is what makes
    // the reservation marker a replay guard.
    if (key === 'stockReservations.intent') {
      const held = (document.stockReservations ?? []).map((entry) =>
        String(entry.intent)
      );
      if (condition && typeof condition === 'object' && '$ne' in condition) {
        if (held.includes(String(condition.$ne))) return false;
      } else if (!held.includes(String(condition))) {
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

  const known = ['$inc', '$push', '$pull'];
  const unknown = Object.keys(update).filter((key) => !known.includes(key));
  if (unknown.length > 0) throw new Error(`unsupported update: ${unknown}`);

  if (update.$push?.stockReservations) {
    const held = document.stockReservations ?? (document.stockReservations = []);
    held.push(update.$push.stockReservations);
  }

  if (update.$pull?.stockReservations) {
    const marker = String(update.$pull.stockReservations.intent);
    document.stockReservations = (document.stockReservations ?? []).filter(
      (entry) => String(entry.intent) !== marker
    );
  }

  const increments = Object.entries(update.$inc ?? {});

  for (const [path, delta] of increments) {
    // R9 terminal reservation failure rotates one Business-wide scalar
    // generation. It is bookkeeping/fencing, not a product-stock increment.
    if (path === 'reservationFence') {
      document.reservationFence =
        Number(document.reservationFence ?? 0) + delta;

      continue;
    }

    const parsed =
      /^products\.\$\[(\w+)\]\.(\w+)$/.exec(path);

    if (!parsed) {
      throw new Error(`unsupported update path: ${path}`);
    }

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

/**
 * Reservation and release now carry a durable identity, so the tests supply
 * one. A distinct id per checkout is what makes replay detectable; passing the
 * SAME id twice is exactly the crash-replay case, and is exercised below.
 */
function buildStockReservation(
  business,
  lines,
  intentId = new mongoose.Types.ObjectId()
) {
  return {
    intentId,

    ...buildIdentifiedReservation({
      businessId: business._id,
      intentId,
      lines,

      // The test must exercise the same authority production passes to the
      // Business write.
      reservationFence: Number(
        business.reservationFence ?? 0
      )
    })
  };
}

function buildStockRelease(business, lines, intentId) {
  return buildIdentifiedRelease({ businessId: business._id, intentId, lines });
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

// ------------------------------------------------------------- variants

test('B04V0 - HTTP checkout accepts only server variant identity, never client display truth', () => {
  const businessIdValue = new mongoose.Types.ObjectId().toString();
  const productIdValue = new mongoose.Types.ObjectId().toString();
  const variantIdValue = new mongoose.Types.ObjectId().toString();

  let accepted = false;

  validateOrderCreate(
    {
      body: {
        businessId: businessIdValue,
        items: [
          {
            productId: productIdValue,
            variantId: variantIdValue,
            quantity: 1
          }
        ]
      }
    },
    undefined,
    () => {
      accepted = true;
    }
  );

  assert.equal(accepted, true);

  assert.throws(
    () =>
      validateOrderCreate(
        {
          body: {
            businessId: businessIdValue,
            items: [
              {
                productId: productIdValue,
                variantId: 'not-an-object-id',
                quantity: 1
              }
            ]
          }
        },
        undefined,
        () => {}
      ),
    (error) => error.code === 'INVALID_PRODUCT_VARIANT_ID'
  );

  assert.throws(
    () =>
      validateOrderCreate(
        {
          body: {
            businessId: businessIdValue,
            items: [
              {
                productId: productIdValue,
                variantId: variantIdValue,
                variant: 'client invented label',
                quantity: 1
              }
            ]
          }
        },
        undefined,
        () => {}
      ),
    (error) => error.code === 'UNSUPPORTED_PRODUCT_VARIANT'
  );
});

test('B04V1 - selected variant price and label are derived from server state', () => {
  const raw = variantProduct({
    price: 100,
    discountPercent: 25,
    variants: [
      {
        label: 'Standard',
        priceOverride: null,
        stock: 5
      },
      {
        label: 'Premium',
        priceOverride: 140,
        stock: 3
      }
    ]
  });
  const business = businessWith([raw]);
  const product = business.products.id(raw._id);
  const premium = product.variants[1];

  const normalized = normalizeRequestedItems([
    {
      ...variantRequest(product, premium, 1),
      // Neither field is authoritative or preserved by normalization.
      unitPrice: 1,
      variant: 'client invented'
    }
  ]);

  assert.equal(normalized.error, undefined);

  const resolved = resolveOrderLines({
    products: business.products,
    items: normalized.items
  });

  assert.equal(resolved.error, undefined);
  assert.equal(resolved.lines.length, 1);

  const [line] = resolved.lines;

  assert.equal(line.variantId, premium._id.toString());
  assert.equal(line.variantLabel, 'Premium');
  assert.equal(line.unitPrice, 105);
  assert.notEqual(line.unitPrice, 1);
});

test('B04V2 - variant mode requires an exact active server-owned variant identity', () => {
  const raw = variantProduct({
    variants: [
      { label: 'Active', stock: 2 },
      { label: 'Inactive', stock: 9, isActive: false }
    ]
  });
  const business = businessWith([raw]);
  const product = business.products.id(raw._id);
  const inactive = product.variants[1];

  const missing = resolveOrderLines({
    products: business.products,
    items: [{ productId: product._id.toString(), quantity: 1 }]
  });

  assert.equal(missing.error, CHECKOUT_ERRORS.variantRequired);

  const foreign = resolveOrderLines({
    products: business.products,
    items: [
      {
        productId: product._id.toString(),
        variantId: new mongoose.Types.ObjectId().toString(),
        quantity: 1
      }
    ]
  });

  assert.equal(foreign.error, CHECKOUT_ERRORS.variantNotAvailable);

  const inactiveResult = resolveOrderLines({
    products: business.products,
    items: [variantRequest(product, inactive, 1)]
  });

  assert.equal(
    inactiveResult.error,
    CHECKOUT_ERRORS.variantNotAvailable
  );
});

test('B04V3 - sibling variants are distinct checkout identities while repeats merge', () => {
  const raw = variantProduct({
    variants: [
      { label: 'Black / M', stock: 10 },
      { label: 'Black / L', stock: 10 }
    ]
  });
  const business = businessWith([raw]);
  const product = business.products.id(raw._id);
  const first = product.variants[0];
  const second = product.variants[1];

  const normalized = normalizeRequestedItems([
    variantRequest(product, first, 1),
    variantRequest(product, second, 4),
    variantRequest(product, first, 2)
  ]);

  assert.equal(normalized.error, undefined);
  assert.deepEqual(normalized.items, [
    {
      productId: product._id.toString(),
      variantId: first._id.toString(),
      quantity: 3
    },
    {
      productId: product._id.toString(),
      variantId: second._id.toString(),
      quantity: 4
    }
  ]);
});

test('B04V4 - variant stock is authoritative even when the parent is unlimited', () => {
  const raw = variantProduct({
    variants: [
      {
        label: 'Scarce',
        unlimitedStock: false,
        stock: 1
      }
    ]
  });
  const business = businessWith([raw]);
  const product = business.products.id(raw._id);
  const variant = product.variants[0];

  const resolved = resolveOrderLines({
    products: business.products,
    items: [variantRequest(product, variant, 2)]
  });

  assert.equal(
    resolved.error,
    CHECKOUT_ERRORS.insufficientStock
  );
  assert.equal(Object.hasOwn(resolved, 'stockQuantity'), false);
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
    buildStockReservation(business, lines)
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
    buildStockReservation(business, lines)
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

  const reservation = buildStockReservation(business, lines);
  // Nothing to consume at all: the reservation records its identity but emits
  // no decrement whatsoever.
  assert.equal(reservation.update.$inc, undefined);
  assert.ok(reservation.update.$push.stockReservations.intent);
  assert.deepEqual(
    reservation.update.$push.stockReservations.lines,
    [],
    'an unlimited basket records a marker holding nothing'
  );

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
    buildStockReservation(business, lines)
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

  // Two different checkouts, so two different reservation identities.
  const firstResult = applyConditionalUpdate(
    business,
    buildStockReservation(business, first)
  );
  const secondResult = applyConditionalUpdate(
    business,
    buildStockReservation(business, second)
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
    buildStockReservation(business, lines)
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

  const reservation = buildStockReservation(business, lines);
  applyConditionalUpdate(business, reservation);
  assert.equal(stockOf(business, finite), 2);

  applyConditionalUpdate(
    business,
    buildStockRelease(business, lines, reservation.intentId)
  );

  assert.equal(stockOf(business, finite), 5, 'stock must be given back exactly');
  assert.equal(stockOf(business, unlimited), 0, 'unlimited stock is never invented');
});

test('B16 - replaying one reservation cannot consume stock twice', () => {
  const product = finiteProduct({ stock: 4 });
  const business = businessWith([product]);
  const lines = linesFor(business, [request(product, 1)]);
  const reservation = buildStockReservation(business, lines);

  const first = applyConditionalUpdate(business, reservation);
  assert.equal(first.matchedCount, 1);
  assert.equal(stockOf(business, product), 3);

  // The crash-replay case: the very same intent reserves again. The marker is
  // already on the document, so the update matches nothing at all.
  const replay = applyConditionalUpdate(business, reservation);
  assert.equal(replay.matchedCount, 0, 'a replay must not match');
  assert.equal(stockOf(business, product), 3, 'and must not decrement again');
});

test('B16 - releasing one reservation twice restores it only once', () => {
  const product = finiteProduct({ stock: 4 });
  const business = businessWith([product]);
  const lines = linesFor(business, [request(product, 1)]);
  const reservation = buildStockReservation(business, lines);
  const release = buildStockRelease(business, lines, reservation.intentId);

  applyConditionalUpdate(business, reservation);
  assert.equal(stockOf(business, product), 3);

  const firstRelease = applyConditionalUpdate(business, release);
  assert.equal(firstRelease.matchedCount, 1);
  assert.equal(stockOf(business, product), 4, 'the unit comes back once');

  // The marker is gone, so a second release cannot match and cannot invent
  // inventory the merchant never had.
  const secondRelease = applyConditionalUpdate(business, release);
  assert.equal(secondRelease.matchedCount, 0);
  assert.equal(stockOf(business, product), 4, 'and never a second time');
});

test('B16 - a release does not over-increment a product turned unlimited', () => {
  const product = finiteProduct({ stock: 4 });
  const business = businessWith([product]);
  const lines = linesFor(business, [request(product, 2)]);
  const reservation = buildStockReservation(business, lines);

  applyConditionalUpdate(business, reservation);
  assert.equal(stockOf(business, product), 2);

  // The merchant switches the product to unlimited mid-checkout.
  const stored = business.products.find((entry) => sameId(entry._id, product._id));
  stored.unlimitedStock = true;

  applyConditionalUpdate(
    business,
    buildStockRelease(business, lines, reservation.intentId)
  );

  // The marker is cleared, but no quantity is handed to a product that no
  // longer counts quantity.
  assert.equal(stockOf(business, product), 2);
  assert.deepEqual(business.stockReservations ?? [], []);
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

test('B18V - an order snapshots variant identity, label, and price independently of later catalog edits', () => {
  const raw = variantProduct({
    price: 100,
    discountPercent: 10,
    variants: [
      {
        label: 'Black / M',
        priceOverride: 120,
        stock: 5
      }
    ]
  });
  const business = businessWith([raw]);
  const product = business.products.id(raw._id);
  const variant = product.variants[0];

  const resolved = resolveOrderLines({
    products: business.products,
    items: [variantRequest(product, variant, 1)]
  });
  assert.equal(resolved.error, undefined);

  const [line] = resolved.lines;

  const order = new Order({
    user: new mongoose.Types.ObjectId(),
    business: business._id,
    businessName: business.name,
    items: [
      {
        productId: line.product._id,
        variantId: line.variantId,
        variant: line.variantLabel,
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

  const storedVariant = product.variants.id(variant._id);
  storedVariant.label = 'Renamed later';
  storedVariant.priceOverride = 999;

  assert.equal(order.items[0].variantId.toString(), variant._id.toString());
  assert.equal(order.items[0].variant, 'Black / M');
  assert.equal(order.items[0].unitPrice, 108);

  const client = order.toClientJSON();
  const merchant = order.toMerchantJSON();

  assert.equal(client.items[0].variantId, variant._id.toString());
  assert.equal(client.items[0].variant, 'Black / M');
  assert.equal(merchant.items[0].variantId, variant._id.toString());
  assert.equal(merchant.items[0].variant, 'Black / M');
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
