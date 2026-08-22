import assert from 'node:assert/strict';
import test from 'node:test';

import mongoose from 'mongoose';

import { Business } from '../src/models/Business.js';
import { CheckoutIntent, checkoutPhases } from '../src/models/CheckoutIntent.js';
import { Order } from '../src/models/Order.js';
import {
  ABANDONED_AFTER_MS,
  CHECKOUT_CLAIMS,
  CLAIMABLE_PHASES,
  CHECKOUT_TRANSITIONS,
  CLAIM_ERRORS,
  FINALIZABLE_PHASES,
  RESERVATION_STATES,
  RESERVATION_TRANSITIONS,
  RECLAIMABLE_PHASES,
  CONVERGENCE_ATTEMPTS,
  CONVERGENCE_INTERVAL_MS,
  IDEMPOTENCY_ERRORS,
  INVENTORY_CONFLICTS,
  INVENTORY_ERRORS,
  buildAtomicInventoryUpdate,
  buildReservationFailure,
  classifyInventoryConflict,
  isLiveReservationEntry,
  isLegalReservationTransition,
  reservedLinesFromMarker,
  buildIdentifiedRelease,
  buildIdentifiedReservation,
  buildReservationSettlement,
  canonicalCheckoutPayload,
  checkoutFingerprint,
  isAbandoned,
  isLegalTransition,
  isResumable,
  isTerminal
} from '../src/policies/checkout-intent.policy.js';
import {
  isFiniteStockProduct,
  normalizeRequestedItems
} from '../src/policies/checkout.policy.js';

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

test('the phases are exactly the six the protocol defines', () => {
  assert.deepEqual(checkoutPhases, [
    'prepared',
    'reserved',
    // The two claims: whoever takes one owns the outcome, and the other is
    // then impossible.
    'finalizing',
    'releasing',
    'finalized',
    'released'
  ]);
});

test('a claim is only ever taken from an unfinished phase', () => {
  assert.deepEqual(CLAIMABLE_PHASES, ['prepared', 'reserved']);
  // Finalized and released are terminal and can never be claimed again.
  for (const terminal of ['finalized', 'released']) {
    assert.equal(CLAIMABLE_PHASES.includes(terminal), false, terminal);
    assert.equal(RECLAIMABLE_PHASES.includes(terminal), false, terminal);
  }
  // A dead worker's claim may be taken over, but only once it is stale.
  assert.deepEqual(RECLAIMABLE_PHASES, [
    'prepared',
    'reserved',
    'finalizing',
    'releasing'
  ]);
  assert.equal(CHECKOUT_CLAIMS.finalizing, 'finalizing');
  assert.equal(CHECKOUT_CLAIMS.releasing, 'releasing');
  assert.equal(CLAIM_ERRORS.lost, 'CHECKOUT_CLAIM_LOST');
});

test('release can never be claimed from a finalizing checkout, stale or not', () => {
  // A finalizing claim is excluded from the ordinary release claim, so a live
  // finalizer cannot have its inventory refunded underneath it...
  assert.equal(CLAIMABLE_PHASES.includes('finalizing'), false);
  // ...and going quiet does not change that. Staleness only decides whether the
  // SAME decision may be resumed by somebody else; it never reverses it.
  assert.equal(isLegalTransition('finalizing', 'releasing'), false);
  assert.equal(isLegalTransition('releasing', 'finalizing'), false);
  // The sweep still has work to do on both, which is a different question.
  assert.equal(RECLAIMABLE_PHASES.includes('finalizing'), true);
  assert.equal(RECLAIMABLE_PHASES.includes('releasing'), true);
});

test('the checkout decision is monotonic', () => {
  // Deciding: an undecided checkout may go either way.
  for (const undecided of CLAIMABLE_PHASES) {
    assert.equal(isLegalTransition(undecided, 'finalizing'), true, undecided);
    assert.equal(isLegalTransition(undecided, 'releasing'), true, undecided);
  }

  // Continuing: a decision may be resumed by another worker in the SAME
  // direction, and completed.
  assert.equal(isLegalTransition('finalizing', 'finalizing'), true);
  assert.equal(isLegalTransition('finalizing', 'finalized'), true);
  assert.equal(isLegalTransition('releasing', 'releasing'), true);
  assert.equal(isLegalTransition('releasing', 'released'), true);

  // Reversing: never, in either direction.
  assert.equal(isLegalTransition('finalizing', 'releasing'), false);
  assert.equal(isLegalTransition('finalizing', 'released'), false);
  assert.equal(isLegalTransition('releasing', 'finalizing'), false);
  assert.equal(isLegalTransition('releasing', 'finalized'), false);

  // Terminal: nothing leaves a terminal phase, to any other phase at all.
  for (const terminal of ['finalized', 'released']) {
    assert.deepEqual(CHECKOUT_TRANSITIONS[terminal], [], terminal);
    for (const phase of checkoutPhases) {
      assert.equal(isLegalTransition(terminal, phase), false, `${terminal}->${phase}`);
    }
  }

  // Every declared edge names a real phase.
  for (const [from, targets] of Object.entries(CHECKOUT_TRANSITIONS)) {
    assert.ok(checkoutPhases.includes(from), from);
    for (const to of targets) assert.ok(checkoutPhases.includes(to), to);
  }
});

test('a reservation outcome is decided once and never rewritten', () => {
  assert.deepEqual(Object.keys(RESERVATION_TRANSITIONS).sort(), [
    'failed',
    'reserved'
  ]);
  // No edges in either direction: an entry is created in its final state, or
  // removed. A checkout that reserved cannot retroactively fail, and one that
  // failed cannot retroactively reserve.
  assert.equal(isLegalReservationTransition('reserved', 'failed'), false);
  assert.equal(isLegalReservationTransition('failed', 'reserved'), false);
  assert.deepEqual(RESERVATION_TRANSITIONS.reserved, []);
  assert.deepEqual(RESERVATION_TRANSITIONS.failed, []);
});

test('a reservation state is internal and is not a checkout phase or a status', () => {
  const publicStatuses = [
    'pending',
    'confirmed',
    'preparing',
    'outForDelivery',
    'delivered',
    'cancelled'
  ];

  // `reserved` deliberately reads the same as the checkout phase of the same
  // name - both mean "stock is held for this checkout" - but they are fields on
  // different documents and no code path assigns one to the other. What must
  // never happen is either of them reaching a customer.
  for (const state of Object.values(RESERVATION_STATES)) {
    assert.equal(publicStatuses.includes(state), false, state);
    assert.equal(
      Order.schema.path('status').enumValues.includes(state),
      false,
      state
    );
  }
  // And it lives on the Business, never on anything a client is handed.
  assert.equal(Order.schema.path('reservationState'), undefined);
  assert.equal(Order.schema.path('stockReservations'), undefined);
});

test('a missing reservation state means the entry is holding stock', () => {
  // Entries written before the field existed only ever recorded live
  // reservations, so the test is a negation on `failed` - never an equality on
  // `reserved`, which would silently ignore every legacy entry and let a
  // merchant edit inventory a checkout is holding.
  assert.equal(isLiveReservationEntry({ intent: 'x' }), true);
  assert.equal(isLiveReservationEntry({ intent: 'x', state: undefined }), true);
  assert.equal(isLiveReservationEntry({ intent: 'x', state: null }), true);
  assert.equal(isLiveReservationEntry({ intent: 'x', state: 'reserved' }), true);
  assert.equal(isLiveReservationEntry({ intent: 'x', state: 'failed' }), false);
  assert.equal(isLiveReservationEntry(null), false);
});

test('a terminal reservation failure competes for the reservation predicate', () => {
  const businessId = new mongoose.Types.ObjectId();
  const intentId = new mongoose.Types.ObjectId();
  const productId = new mongoose.Types.ObjectId();

  const failure = buildReservationFailure({
    businessId,
    intentId,
    failureCode: 'INSUFFICIENT_STOCK'
  });
  const reservation = buildIdentifiedReservation({
    businessId,
    intentId,
    lines: [{ productId, quantity: 2, finite: true }]
  });

  // THE point of the design: both are a push into the same array, guarded by
  // the same predicate on the same document, so exactly one can land.
  assert.deepEqual(failure.filter['stockReservations.intent'], { $ne: intentId });
  assert.deepEqual(reservation.filter['stockReservations.intent'], {
    $ne: intentId
  });
  assert.ok(failure.update.$push.stockReservations);
  assert.ok(reservation.update.$push.stockReservations);

  // A refusal holds nothing and can never be read as consumption.
  const entry = failure.update.$push.stockReservations;
  assert.equal(entry.state, RESERVATION_STATES.failed);
  assert.deepEqual(entry.lines, []);
  assert.equal(entry.failureCode, 'INSUFFICIENT_STOCK');
  assert.equal(failure.update.$inc, undefined, 'a refusal never touches stock');

  // And the reservation still records what it actually took.
  assert.equal(
    reservation.update.$push.stockReservations.state,
    RESERVATION_STATES.reserved
  );
});

test('a refusal record is never compensated as if it were stock', () => {
  const intentId = new mongoose.Types.ObjectId();
  const productId = new mongoose.Types.ObjectId();

  const refused = {
    stockReservations: [
      { intent: intentId, state: 'failed', failureCode: 'INSUFFICIENT_STOCK', lines: [] }
    ]
  };
  assert.equal(reservedLinesFromMarker(refused, intentId), null);

  // A live entry is still authoritative, exactly as R6 left it.
  const held = {
    stockReservations: [
      { intent: intentId, state: 'reserved', lines: [{ productId, quantity: 2 }] }
    ]
  };
  assert.deepEqual(reservedLinesFromMarker(held, intentId), [
    { productId, quantity: 2, finite: true }
  ]);

  // A legacy entry with no state at all is still a live reservation.
  const legacy = {
    stockReservations: [{ intent: intentId, lines: [{ productId, quantity: 3 }] }]
  };
  assert.deepEqual(reservedLinesFromMarker(legacy, intentId), [
    { productId, quantity: 3, finite: true }
  ]);
});

test('a refusal record is not reported to a merchant as a reservation', () => {
  const business = {
    isActive: true,
    stockReservations: [{ intent: new mongoose.Types.ObjectId(), state: 'failed', lines: [] }]
  };
  const product = { _id: new mongoose.Types.ObjectId(), unlimitedStock: false, stockQuantity: 4 };

  // It holds no stock, so the honest answer is the compare-and-set, not
  // "somebody is holding your inventory".
  assert.equal(
    classifyInventoryConflict({ business, product, observedStock: { unlimitedStock: false, stockQuantity: 9 } }),
    INVENTORY_CONFLICTS.stockChanged
  );

  // A live one is still reported as a reservation.
  const holding = {
    isActive: true,
    stockReservations: [{ intent: new mongoose.Types.ObjectId(), state: 'reserved', lines: [] }]
  };
  assert.equal(
    classifyInventoryConflict({ business: holding, product, observedStock: { unlimitedStock: false, stockQuantity: 4 } }),
    INVENTORY_CONFLICTS.reserved
  );
});

test('a releasing checkout can never be adopted onto an order', () => {
  // The set recovery uses when a durable order is found. `releasing` is absent
  // on purpose: once release owns the outcome, no order belongs to it.
  assert.deepEqual(FINALIZABLE_PHASES, ['prepared', 'reserved', 'finalizing']);
  assert.equal(FINALIZABLE_PHASES.includes('releasing'), false);
  assert.equal(FINALIZABLE_PHASES.includes('released'), false);
  assert.equal(FINALIZABLE_PHASES.includes('finalized'), false);
});

test('the finalization snapshot is internal and never selected by default', () => {
  const path = CheckoutIntent.schema.path('finalization');
  assert.ok(path, 'the snapshot is a declared field');
  assert.equal(path.options.select, false, 'never returned unless asked for');

  // No customer- or merchant-facing model can carry it, so no serializer of
  // theirs could ever leak it.
  assert.equal(Order.schema.path('finalization'), undefined);
  assert.equal(Business.schema.path('finalization'), undefined);

  // The reservation marker is the same kind of secret and is already proven
  // unselectable; the snapshot is held to the identical rule.
  assert.equal(
    Business.schema.path('stockReservations').options.select,
    false
  );
});

test('internal claims never reach a public order status', () => {
  const publicStatuses = [
    'pending',
    'confirmed',
    'preparing',
    'outForDelivery',
    'delivered',
    'cancelled'
  ];
  for (const claim of Object.values(CHECKOUT_CLAIMS)) {
    assert.equal(publicStatuses.includes(claim), false, claim);
  }
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
  assert.deepEqual(reservation.filter['stockReservations.intent'], { $ne: intentId });
  // The decrement and the marker are one update, never two.
  assert.equal(String(reservation.update.$push.stockReservations.intent), String(intentId));
  assert.equal(Object.keys(reservation.update.$inc).length, 1, 'only the finite line');
  assert.equal(Object.values(reservation.update.$inc)[0], -2);
});

test('a release only runs while the reservation is outstanding', () => {
  const release = buildIdentifiedRelease({ businessId, intentId, lines: lines() });

  assert.equal(release.filter['stockReservations.intent'], intentId);
  assert.deepEqual(release.update.$pull, { stockReservations: { intent: intentId } });
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
      built.filter['stockReservations.intent'] !== undefined,
      'every stock write is guarded by the reservation marker'
    );
  }
});

test('settling a finalized reservation clears the marker without refunding', () => {
  const settlement = buildReservationSettlement({ businessId, intentId });

  assert.equal(settlement.filter['stockReservations.intent'], intentId);
  assert.deepEqual(settlement.update, {
    $pull: { stockReservations: { intent: intentId } }
  });
  assert.equal(settlement.update.$inc, undefined, 'a finalized order keeps its stock');
});

test('an unlimited-only basket records identity but decrements nothing', () => {
  const reservation = buildIdentifiedReservation({
    businessId,
    intentId,
    lines: [{ productId: new mongoose.Types.ObjectId(), quantity: 5, finite: false }]
  });

  assert.equal(reservation.update.$inc, undefined);
  assert.equal(String(reservation.update.$push.stockReservations.intent), String(intentId));
});

// ------------------------------------------------- stock-mode symmetry (R5)

test('U01/U02 a finite line asserts it is still finite and still stocked', () => {
  const productId = new mongoose.Types.ObjectId();
  const reservation = buildIdentifiedReservation({
    businessId,
    intentId,
    lines: [{ productId, quantity: 3, finite: true }]
  });

  const [clause] = reservation.filter.$and;
  const criteria = clause.products.$elemMatch;

  assert.equal(criteria.unlimitedStock, false, 'U01: still finite');
  assert.deepEqual(criteria.stockQuantity, { $gte: 3 }, 'U02: still stocked');
});

test('U03/U04/U05 a non-finite line asserts it is still non-finite', () => {
  const productId = new mongoose.Types.ObjectId();
  const reservation = buildIdentifiedReservation({
    businessId,
    intentId,
    lines: [{ productId, quantity: 4, finite: false }]
  });

  const criteria = reservation.filter.$and[0].products.$elemMatch;

  // U03 - an explicitly finite product is rejected...
  assert.deepEqual(criteria.unlimitedStock, { $ne: false });
  // ...and the predicate is present at all, which is the whole R5 defect.
  assert.notEqual(
    criteria.unlimitedStock,
    undefined,
    'a non-finite line must still assert its stock mode'
  );

  // U04/U05 - `$ne: false` accepts `true`, a missing field and `null`, which is
  // exactly the negation of isFiniteStockProduct. Asserted against the real
  // predicate semantics rather than restated as a comment.
  for (const shape of [{ unlimitedStock: true }, {}, { unlimitedStock: null }]) {
    assert.equal(
      isFiniteStockProduct(shape),
      false,
      `${JSON.stringify(shape)} must read as non-finite`
    );
    assert.notEqual(shape.unlimitedStock, false, 'and must satisfy $ne:false');
  }

  assert.equal(isFiniteStockProduct({ unlimitedStock: false }), true);
});

test('U06 no line can reserve on identity and activity alone', () => {
  const productId = new mongoose.Types.ObjectId();

  for (const finite of [true, false]) {
    const reservation = buildIdentifiedReservation({
      businessId,
      intentId,
      lines: [{ productId, quantity: 2, finite }]
    });
    const criteria = reservation.filter.$and[0].products.$elemMatch;

    // Identity and activity are never sufficient on their own: every line
    // carries a stock-mode assertion too.
    assert.deepEqual(
      Object.keys(criteria).sort(),
      finite
        ? ['_id', 'isActive', 'stockQuantity', 'unlimitedStock']
        : ['_id', 'isActive', 'unlimitedStock'],
      `finite=${finite}`
    );
  }
});

test('U06 the replay guard is untouched by the stock-mode work', () => {
  const reservation = buildIdentifiedReservation({
    businessId,
    intentId,
    lines: [{ productId: new mongoose.Types.ObjectId(), quantity: 1, finite: false }]
  });

  assert.deepEqual(reservation.filter['stockReservations.intent'], { $ne: intentId });
  // A non-finite basket still consumes nothing.
  assert.equal(reservation.update.$inc, undefined);
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
  // Only entries HOLDING stock block the write. A terminal-failure record
  // holds nothing, so it must not freeze a merchant's inventory.
  assert.deepEqual(atomic.filter.stockReservations, {
    $not: { $elemMatch: { state: { $ne: 'failed' } } }
  });
  assert.equal(atomic.filter['stockReservations.0'], undefined);
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
  // Only entries HOLDING stock block the write. A terminal-failure record
  // holds nothing, so it must not freeze a merchant's inventory.
  assert.deepEqual(atomic.filter.stockReservations, {
    $not: { $elemMatch: { state: { $ne: 'failed' } } }
  });
  assert.equal(atomic.filter['stockReservations.0'], undefined);
});

test('an unlimited observation asserts only the mode, not a phantom quantity', () => {
  // A legacy document stores no `unlimitedStock`, but Mongoose reads it back as
  // `true`. Asserting `true` literally would compare against a field that is
  // absent on disk and refuse every edit to such a product.
  const atomic = buildAtomicInventoryUpdate({
    businessId,
    ownerId: new mongoose.Types.ObjectId(),
    productId: new mongoose.Types.ObjectId(),
    write: { unlimitedStock: false, stockQuantity: 5 },
    observedStock: { stockQuantity: 0, unlimitedStock: true }
  });

  const criteria = atomic.filter.products.$elemMatch;
  assert.deepEqual(criteria.unlimitedStock, { $ne: false });
  assert.equal(
    criteria.stockQuantity,
    undefined,
    'a quantity is meaningless while unlimited'
  );
  // The reservation guard is never optional.
  // Only entries HOLDING stock block the write. A terminal-failure record
  // holds nothing, so it must not freeze a merchant's inventory.
  assert.deepEqual(atomic.filter.stockReservations, {
    $not: { $elemMatch: { state: { $ne: 'failed' } } }
  });
  assert.equal(atomic.filter['stockReservations.0'], undefined);
});

test('a finite observation still asserts the exact pair', () => {
  const atomic = buildAtomicInventoryUpdate({
    businessId,
    ownerId: new mongoose.Types.ObjectId(),
    productId: new mongoose.Types.ObjectId(),
    write: { stockQuantity: 10 },
    observedStock: { stockQuantity: 5, unlimitedStock: false }
  });

  const criteria = atomic.filter.products.$elemMatch;
  assert.equal(criteria.unlimitedStock, false);
  assert.equal(criteria.stockQuantity, 5);
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
  // Only entries HOLDING stock block the write. A terminal-failure record
  // holds nothing, so it must not freeze a merchant's inventory.
  assert.deepEqual(atomic.filter.stockReservations, {
    $not: { $elemMatch: { state: { $ne: 'failed' } } }
  });
  assert.equal(atomic.filter['stockReservations.0'], undefined);
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
    stockReservations: [{ intent: intentId, lines: [] }]
  });

  for (const json of [business.toListJSON(), business.toDetailJSON(), business.toOwnerJSON()]) {
    assert.equal(Object.hasOwn(json, 'stockReservations'), false);
  }
});
