import assert from 'node:assert/strict';
import test from 'node:test';

import mongoose from 'mongoose';

import { Business } from '../src/models/Business.js';
import { CheckoutIntent, checkoutPhases } from '../src/models/CheckoutIntent.js';
import { Order } from '../src/models/Order.js';
import {
  ABANDONED_AFTER_MS,
  CONVERGENCE_ATTEMPTS,
  CONVERGENCE_INTERVAL_MS,
  IDEMPOTENCY_ERRORS,
  INVENTORY_CONFLICTS,
  INVENTORY_ERRORS,
  buildAtomicInventoryUpdate,
  classifyInventoryConflict,
  buildIdentifiedRelease,
  buildIdentifiedReservation,
  buildReservationSettlement,
  canonicalCheckoutPayload,
  checkoutFingerprint,
  isAbandoned,
  isResumable,
  isTerminal
} from '../src/policies/checkout-intent.policy.js';
import { normalizeRequestedItems } from '../src/policies/checkout.policy.js';

/**
 * MERZOX-GAP-002-R1 checkout state machine, without a database.
 *
 * These cover the parts that are pure decisions: what makes two requests the
 * same request, which phases may still do work, and the shape of the guards
 * that make a reservation and its release impossible to apply twice.
 *
 * The behaviour of those guards against a real server is proved separately by
 * the guarded inventory integration suite.
 */

const ID_A = '64c000000000000000000001';
const ID_B = '64c000000000000000000002';

function basePayload(overrides = {}) {
  return {
    businessId: '64b000000000000000000001',
    items: [
      { productId: ID_A, quantity: 2 },
      { productId: ID_B, quantity: 1 }
    ],
    deliveryAddress: 'شارع الاختبار 12',
    paymentMethod: 'cash',
    ...overrides
  };
}

// ------------------------------------------------------------- fingerprinting

test('the fingerprint is stable for an identical request', () => {
  assert.equal(checkoutFingerprint(basePayload()), checkoutFingerprint(basePayload()));
});

test('the fingerprint ignores the order the client happened to send items in', () => {
  const permuted = basePayload({
    items: [
      { productId: ID_B, quantity: 1 },
      { productId: ID_A, quantity: 2 }
    ]
  });

  assert.equal(checkoutFingerprint(basePayload()), checkoutFingerprint(permuted));
});

test('a repeated product id fingerprints as its normalized summed line', () => {
  const repeated = normalizeRequestedItems([
    { productId: ID_A, quantity: 1 },
    { productId: ID_B, quantity: 1 },
    { productId: ID_A, quantity: 1 }
  ]);
  const summed = normalizeRequestedItems([
    { productId: ID_A, quantity: 2 },
    { productId: ID_B, quantity: 1 }
  ]);

  assert.equal(
    checkoutFingerprint(basePayload({ items: repeated.items })),
    checkoutFingerprint(basePayload({ items: summed.items }))
  );
});

test('surrounding whitespace does not change the request', () => {
  assert.equal(
    checkoutFingerprint(basePayload()),
    checkoutFingerprint(basePayload({ deliveryAddress: '  شارع الاختبار 12  ' }))
  );
});

test('every customer-controlled field changes the fingerprint', () => {
  const baseline = checkoutFingerprint(basePayload());

  const changes = [
    basePayload({ businessId: '64b000000000000000000009' }),
    basePayload({ items: [{ productId: ID_A, quantity: 3 }, { productId: ID_B, quantity: 1 }] }),
    basePayload({ items: [{ productId: ID_A, quantity: 2 }] }),
    basePayload({ deliveryAddress: 'عنوان آخر تماماً' }),
    basePayload({ paymentMethod: 'card' })
  ];

  for (const [index, changed] of changes.entries()) {
    assert.notEqual(checkoutFingerprint(changed), baseline, `change ${index}`);
  }
});

test('the canonical payload carries no secret and no server-derived price', () => {
  const canonical = canonicalCheckoutPayload({
    ...basePayload(),
    token: 'gho_secret_value',
    password: 'hunter2',
    unitPrice: 75,
    finalPrice: 75
  });
  const serialized = JSON.stringify(canonical);

  for (const forbidden of ['gho_secret_value', 'hunter2', 'unitPrice', 'finalPrice', '75']) {
    assert.equal(
      serialized.includes(forbidden),
      false,
      `canonical payload must not contain ${forbidden}`
    );
  }
  assert.deepEqual(Object.keys(canonical).sort(), [
    'businessId',
    'deliveryAddress',
    'items',
    'paymentMethod'
  ]);
});

// ------------------------------------------------------------- phase legality

test('the phases are exactly the four the protocol defines', () => {
  assert.deepEqual(checkoutPhases, ['prepared', 'reserved', 'finalized', 'released']);
});

test('only unfinished phases may still do work', () => {
  assert.equal(isResumable('prepared'), true);
  assert.equal(isResumable('reserved'), true);
  assert.equal(isResumable('finalized'), false);
  assert.equal(isResumable('released'), false);

  assert.equal(isTerminal('finalized'), true);
  assert.equal(isTerminal('released'), true);
  assert.equal(isTerminal('prepared'), false);
  assert.equal(isTerminal('reserved'), false);
});

test('internal phases are not public delivery statuses', () => {
  const publicStatuses = [
    'pending',
    'confirmed',
    'preparing',
    'outForDelivery',
    'delivered',
    'cancelled'
  ];

  for (const phase of checkoutPhases) {
    assert.equal(
      publicStatuses.includes(phase),
      false,
      `${phase} must not collide with a public order status`
    );
  }
});

test('the intent identity is unique per user and client order id', () => {
  const idempotency = CheckoutIntent.schema
    .indexes()
    .find(([fields]) => fields.user === 1 && fields.clientOrderId === 1);

  assert.ok(idempotency, 'expected a {user, clientOrderId} index');
  assert.equal(idempotency[1].unique, true);
});

test('convergence polling is bounded', () => {
  assert.ok(Number.isInteger(CONVERGENCE_ATTEMPTS) && CONVERGENCE_ATTEMPTS > 0);
  assert.ok(CONVERGENCE_ATTEMPTS < 100, 'the bound must stay small');
  assert.ok(CONVERGENCE_INTERVAL_MS > 0);
  assert.ok(
    CONVERGENCE_ATTEMPTS * CONVERGENCE_INTERVAL_MS <= 5000,
    'a losing request must not hang a connection for long'
  );
  assert.equal(IDEMPOTENCY_ERRORS.inProgress, 'CHECKOUT_IN_PROGRESS');
});

test('an intent is only abandoned after the whole convergence window', () => {
  const now = Date.UTC(2026, 0, 1, 12, 0, 0);

  const fresh = { updatedAt: new Date(now - 10) };
  const borderline = { updatedAt: new Date(now - ABANDONED_AFTER_MS) };
  const stale = { updatedAt: new Date(now - ABANDONED_AFTER_MS - 1) };

  assert.equal(isAbandoned(fresh, now), false, 'a live worker is waited for');
  assert.equal(isAbandoned(borderline, now), false, 'the boundary still waits');
  assert.equal(isAbandoned(stale, now), true, 'a dead worker is taken over');

  // An intent with no timestamps at all is never assumed dead.
  assert.equal(isAbandoned({}, now), false);
  assert.equal(isAbandoned(null, now), false);
});

// ------------------------------------------------------------- guard shapes

const businessId = new mongoose.Types.ObjectId();
const intentId = new mongoose.Types.ObjectId();

function lines() {
  return [
    { productId: new mongoose.Types.ObjectId(), quantity: 2, finite: true },
    { productId: new mongoose.Types.ObjectId(), quantity: 1, finite: false }
  ];
}

test('a reservation refuses to run twice for the same identity', () => {
  const reservation = buildIdentifiedReservation({
    businessId,
    intentId,
    lines: lines()
  });

  // The replay guard.
  assert.deepEqual(reservation.filter.stockReservations, { $ne: intentId });
  // The decrement and the marker are one update, never two.
  assert.deepEqual(reservation.update.$addToSet, { stockReservations: intentId });
  assert.equal(Object.keys(reservation.update.$inc).length, 1, 'only the finite line');
  assert.equal(Object.values(reservation.update.$inc)[0], -2);
});

test('a release only runs while the reservation is outstanding', () => {
  const release = buildIdentifiedRelease({ businessId, intentId, lines: lines() });

  assert.equal(release.filter.stockReservations, intentId);
  assert.deepEqual(release.update.$pull, { stockReservations: intentId });
  assert.equal(Object.values(release.update.$inc)[0], 2, 'exactly what was taken');
  // A merchant switching the product to unlimited must not be handed stock.
  assert.equal(release.arrayFilters[0]['line0.unlimitedStock'], false);
});

test('no builder emits an unconditional stock increment', () => {
  for (const built of [
    buildIdentifiedReservation({ businessId, intentId, lines: lines() }),
    buildIdentifiedRelease({ businessId, intentId, lines: lines() })
  ]) {
    assert.ok(
      built.filter.stockReservations !== undefined,
      'every stock write is guarded by the reservation marker'
    );
  }
});

test('settling a finalized reservation clears the marker without refunding', () => {
  const settlement = buildReservationSettlement({ businessId, intentId });

  assert.equal(settlement.filter.stockReservations, intentId);
  assert.deepEqual(settlement.update, { $pull: { stockReservations: intentId } });
  assert.equal(settlement.update.$inc, undefined, 'a finalized order keeps its stock');
});

test('an unlimited-only basket records identity but decrements nothing', () => {
  const reservation = buildIdentifiedReservation({
    businessId,
    intentId,
    lines: [{ productId: new mongoose.Types.ObjectId(), quantity: 5, finite: false }]
  });

  assert.equal(reservation.update.$inc, undefined);
  assert.deepEqual(reservation.update.$addToSet, { stockReservations: intentId });
});

// ------------------------------------------------ atomic merchant inventory

test('the merchant inventory write carries its own reservation predicate', () => {
  const productId = new mongoose.Types.ObjectId();
  const ownerId = new mongoose.Types.ObjectId();

  const atomic = buildAtomicInventoryUpdate({
    businessId,
    ownerId,
    productId,
    write: { stockQuantity: 10, unlimitedStock: false, description: 'new' },
    observedStock: { stockQuantity: 5, unlimitedStock: false }
  });

  // The whole point of R3: reservation absence is evaluated by MongoDB at
  // write time, in the same operation that changes the stock.
  assert.deepEqual(atomic.filter['stockReservations.0'], { $exists: false });
  assert.equal(atomic.update.$set['products.$[product].stockQuantity'], 10);
  assert.equal(atomic.update.$set['products.$[product].unlimitedStock'], false);

  // Ownership is part of the write, never inferred from a request body.
  assert.equal(atomic.filter.owner, ownerId);
  assert.equal(atomic.filter._id, businessId);
  assert.equal(atomic.filter.isActive, true);

  // Compare-and-set on the pair the caller derived its write from.
  assert.equal(atomic.filter.products.$elemMatch.stockQuantity, 5);
  assert.equal(atomic.filter.products.$elemMatch.unlimitedStock, false);
  assert.deepEqual(atomic.arrayFilters, [{ 'product._id': productId }]);
});

test('a mixed payload is one write, so it cannot half-apply', () => {
  const productId = new mongoose.Types.ObjectId();

  const atomic = buildAtomicInventoryUpdate({
    businessId,
    ownerId: new mongoose.Types.ObjectId(),
    productId,
    write: { stockQuantity: 10, description: 'new description', price: 42 },
    observedStock: { stockQuantity: 5, unlimitedStock: false }
  });

  // Every field rides on the same guarded update: if the filter misses, none
  // of them is written.
  assert.deepEqual(Object.keys(atomic.update.$set).sort(), [
    'products.$[product].description',
    'products.$[product].price',
    'products.$[product].stockQuantity'
  ]);
  assert.equal(Object.keys(atomic.update).length, 1, 'a single $set operator');
  assert.deepEqual(atomic.filter['stockReservations.0'], { $exists: false });
});

test('a legacy product without a stock pair is not refused on a phantom field', () => {
  const atomic = buildAtomicInventoryUpdate({
    businessId,
    ownerId: new mongoose.Types.ObjectId(),
    productId: new mongoose.Types.ObjectId(),
    write: { stockQuantity: 3, unlimitedStock: false },
    observedStock: { stockQuantity: undefined, unlimitedStock: undefined }
  });

  // No compare-and-set on values the document never carried...
  assert.equal(atomic.filter.products.$elemMatch.stockQuantity, undefined);
  assert.equal(atomic.filter.products.$elemMatch.unlimitedStock, undefined);
  // ...but the reservation guard is never optional.
  assert.deepEqual(atomic.filter['stockReservations.0'], { $exists: false });
});

test('the merchant conflict codes are stable and distinct', () => {
  assert.equal(INVENTORY_ERRORS.reserved, 'PRODUCT_INVENTORY_RESERVED');
  assert.equal(INVENTORY_ERRORS.changed, 'PRODUCT_INVENTORY_CHANGED');
  assert.notEqual(INVENTORY_ERRORS.reserved, INVENTORY_ERRORS.changed);
});

// --------------------------------------------------- conflict classification

const observedStock = { stockQuantity: 5, unlimitedStock: false };

function businessLike({ isActive = true, reservations = [], product } = {}) {
  return {
    isActive,
    stockReservations: reservations,
    products: { id: () => product }
  };
}

test('an outstanding reservation is reported as a reservation', () => {
  const conflict = classifyInventoryConflict({
    business: businessLike({
      reservations: [new mongoose.Types.ObjectId()],
      product: { stockQuantity: 3, unlimitedStock: false }
    }),
    product: { stockQuantity: 3, unlimitedStock: false },
    observedStock
  });

  assert.equal(conflict, INVENTORY_CONFLICTS.reserved);
});

test('a stale stock pair is NOT reported as a reservation', () => {
  // The exact case R4 exists for: nothing is holding stock, the merchant is
  // simply looking at a number that moved.
  const conflict = classifyInventoryConflict({
    business: businessLike({
      reservations: [],
      product: { stockQuantity: 3, unlimitedStock: false }
    }),
    product: { stockQuantity: 3, unlimitedStock: false },
    observedStock
  });

  assert.equal(conflict, INVENTORY_CONFLICTS.stockChanged);
  assert.notEqual(conflict, INVENTORY_CONFLICTS.reserved);
});

test('a changed unlimited flag is also a change, not a reservation', () => {
  const conflict = classifyInventoryConflict({
    business: businessLike({
      reservations: [],
      product: { stockQuantity: 0, unlimitedStock: true }
    }),
    product: { stockQuantity: 0, unlimitedStock: true },
    observedStock
  });

  assert.equal(conflict, INVENTORY_CONFLICTS.stockChanged);
});

test('a missing product or business keeps its own meaning', () => {
  assert.equal(
    classifyInventoryConflict({ business: null, product: null, observedStock }),
    INVENTORY_CONFLICTS.businessMissing
  );
  assert.equal(
    classifyInventoryConflict({
      business: businessLike({ isActive: false }),
      product: { stockQuantity: 5, unlimitedStock: false },
      observedStock
    }),
    INVENTORY_CONFLICTS.businessInactive
  );
  assert.equal(
    classifyInventoryConflict({
      business: businessLike({ reservations: [] }),
      product: null,
      observedStock
    }),
    INVENTORY_CONFLICTS.productMissing
  );
});

test('classification is pure: it can never write', () => {
  // Given only plain objects with no save/update surface at all, the classifier
  // still returns an answer - proof that it performs no second inventory write.
  const inert = Object.freeze({
    isActive: true,
    stockReservations: Object.freeze([]),
    products: Object.freeze({ id: () => Object.freeze({ stockQuantity: 3, unlimitedStock: false }) })
  });

  assert.equal(
    classifyInventoryConflict({
      business: inert,
      product: inert.products.id(),
      observedStock
    }),
    INVENTORY_CONFLICTS.stockChanged
  );
  assert.equal(typeof classifyInventoryConflict, 'function');
});

// ------------------------------------------------------- provisional privacy

test('an unfinished checkout is not an order at all', () => {
  // The strongest possible answer to "can a provisional record leak into a
  // listing": there is no provisional order document to leak. Intents live in
  // their own collection and are never serialized.
  assert.notEqual(CheckoutIntent.collection.name, Order.collection.name);
  assert.equal(typeof CheckoutIntent.schema.methods.toClientJSON, 'undefined');
  assert.equal(typeof CheckoutIntent.schema.methods.toMerchantJSON, 'undefined');
});

test('the reservation marker is never selected into a business response', () => {
  const path = Business.schema.path('stockReservations');

  assert.ok(path, 'expected the marker field to exist');
  assert.equal(path.options.select, false, 'it must not load by default');

  const business = new Business({
    owner: new mongoose.Types.ObjectId(),
    publicId: 'MXB-GAP002R1',
    name: 'متجر',
    category: 'فئة',
    stockReservations: [intentId]
  });

  for (const json of [business.toListJSON(), business.toDetailJSON(), business.toOwnerJSON()]) {
    assert.equal(Object.hasOwn(json, 'stockReservations'), false);
  }
});
