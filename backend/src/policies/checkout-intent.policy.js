import crypto from 'node:crypto';

/**
 * The idempotency and recovery rules for one checkout.
 *
 * Two things live here, both deliberately free of I/O so they can be tested
 * exhaustively without a database:
 *
 *   1. the canonical fingerprint that decides whether two requests carrying the
 *      same client order id are the SAME request or a key being reused, and
 *   2. the reservation-marker filters that make a stock decrement and its
 *      release idempotent, so neither can be applied twice.
 */

/** Bounded convergence for a losing concurrent request. Never unbounded. */
export const CONVERGENCE_ATTEMPTS = 25;
export const CONVERGENCE_INTERVAL_MS = 120;

/**
 * How long an unfinished intent may sit untouched before a new request stops
 * waiting for its owner and takes the work over.
 *
 * A live worker updates the intent as it moves through the phases, so silence
 * for longer than the whole convergence window means nobody is driving it -
 * almost certainly a crash. Waiting the full window again would punish every
 * recovery for a worker that is never coming back.
 */
export const ABANDONED_AFTER_MS = CONVERGENCE_ATTEMPTS * CONVERGENCE_INTERVAL_MS;

export function isAbandoned(intent, now) {
  const touched = intent?.updatedAt ?? intent?.createdAt;
  if (!touched) return false;

  return now - new Date(touched).getTime() > ABANDONED_AFTER_MS;
}

/**
 * How long a non-terminal checkout may go untouched before the autonomous
 * reconciler presumes its client is never coming back.
 *
 * This is NOT the request-path convergence wait above. That one is short
 * because a person is waiting on an HTTP response; this one is long because
 * taking over a checkout that is merely slow would be worse than waiting.
 */
export const CHECKOUT_STALE_LEASE_MS = 2 * 60 * 1000;

/** How often the background sweep runs. Bounded, and never a tight loop. */
export const RECONCILE_INTERVAL_MS = 60 * 1000;

/** The most intents one sweep will touch, so a backlog cannot stall a process. */
export const RECONCILE_BATCH_LIMIT = 200;

export const INVENTORY_ERRORS = {
  /**
   * A merchant tried to rewrite stock while a checkout still holds some of it.
   * Refused rather than merged: the outstanding reservation will be released or
   * settled within the lease above, and the edit succeeds on retry.
   */
  reserved: 'PRODUCT_INVENTORY_RESERVED'
};

/**
 * The intents that currently hold inventory for one product.
 *
 * Scoped to reservations the business still lists as outstanding, so a settled
 * or released checkout never blocks a merchant. `$elemMatch` matters: the line
 * must be BOTH this product and finite, not two different lines that happen to
 * satisfy one condition each.
 */
export function outstandingReservationFilter({ outstandingIds, productId }) {
  return {
    _id: { $in: outstandingIds },
    phase: { $in: ['prepared', 'reserved'] },
    lines: { $elemMatch: { productId, finite: true } }
  };
}

export const IDEMPOTENCY_ERRORS = {
  keyReused: 'IDEMPOTENCY_KEY_REUSED',
  inProgress: 'CHECKOUT_IN_PROGRESS'
};

/**
 * Reduces a checkout request to the customer-controlled facts that define it.
 *
 * Only semantics survive: items are normalized and sorted, strings are trimmed,
 * and nothing server-derived enters the hash. A sale price is NOT included -
 * the server owns it, so a merchant repricing between a request and its retry
 * must not turn a legitimate retry into a key conflict.
 *
 * Deliberately absent: tokens, passwords, any secret, and any header. The value
 * is a hash of public request content and is never returned to a client.
 */
export function canonicalCheckoutPayload({
  businessId,
  items,
  deliveryAddress,
  paymentMethod
}) {
  return {
    businessId: String(businessId ?? '').trim(),
    // Already duplicate-merged by `normalizeRequestedItems`; sorting makes the
    // fingerprint independent of the order the client happened to send.
    items: [...(items ?? [])]
      .map((item) => ({
        productId: String(item.productId ?? '').trim(),
        quantity: Number(item.quantity)
      }))
      .sort((left, right) => left.productId.localeCompare(right.productId)),
    deliveryAddress: String(deliveryAddress ?? '').trim(),
    paymentMethod: String(paymentMethod ?? 'cash').trim()
  };
}

export function checkoutFingerprint(payload) {
  return crypto
    .createHash('sha256')
    .update(JSON.stringify(canonicalCheckoutPayload(payload)))
    .digest('hex');
}

/** The phases from which a retry may still do work. */
export function isResumable(phase) {
  return phase === 'prepared' || phase === 'reserved';
}

export function isTerminal(phase) {
  return phase === 'finalized' || phase === 'released';
}

/**
 * The reservation, now carrying its own identity.
 *
 * The `$inc` and the `$addToSet` of the intent id are one single-document
 * update, so "stock was decremented" and "this intent decremented it" become a
 * single atomic fact. There is no window in which one is true and the other is
 * not.
 *
 * The filter refuses a business that already carries this intent id, which is
 * what makes the operation idempotent: replaying it after a crash matches
 * nothing instead of decrementing a second time.
 */
export function buildIdentifiedReservation({ businessId, intentId, lines }) {
  const finiteLines = lines.filter((line) => line.finite);

  const filter = {
    _id: businessId,
    isActive: true,
    // Never twice for the same intent.
    stockReservations: { $ne: intentId },
    $and: lines.map((line) => ({
      products: {
        $elemMatch: {
          _id: line.product?._id ?? line.productId,
          isActive: true,
          ...(line.finite
            ? { unlimitedStock: false, stockQuantity: { $gte: line.quantity } }
            : {})
        }
      }
    }))
  };

  const increments = {};
  const arrayFilters = finiteLines.map((line, index) => {
    const alias = `line${index}`;
    increments[`products.$[${alias}].stockQuantity`] = -line.quantity;

    return {
      [`${alias}._id`]: line.product?._id ?? line.productId,
      [`${alias}.unlimitedStock`]: false,
      [`${alias}.stockQuantity`]: { $gte: line.quantity }
    };
  });

  const update = { $addToSet: { stockReservations: intentId } };
  if (finiteLines.length > 0) update.$inc = increments;

  return { filter, update, arrayFilters };
}

/**
 * The compensating release, guarded by the same identity.
 *
 * `$pull` and `$inc` are one update, and the filter requires the marker to
 * still be present, so a second release matches nothing and changes nothing.
 * That is the whole double-release guarantee - there is no unconditional
 * `$inc stockQuantity + quantity` anywhere.
 *
 * The array filters keep `unlimitedStock: false`. If a merchant switched the
 * product to unlimited while the checkout was in flight, the marker is still
 * cleared but no quantity is added back: giving stock to a product that no
 * longer counts stock would invent inventory the merchant never had.
 */
export function buildIdentifiedRelease({ businessId, intentId, lines }) {
  const finiteLines = lines.filter((line) => line.finite);

  const filter = {
    _id: businessId,
    // Only a reservation that is still outstanding can be released.
    stockReservations: intentId
  };

  const increments = {};
  const arrayFilters = finiteLines.map((line, index) => {
    const alias = `line${index}`;
    increments[`products.$[${alias}].stockQuantity`] = line.quantity;

    return {
      [`${alias}._id`]: line.product?._id ?? line.productId,
      [`${alias}.unlimitedStock`]: false
    };
  });

  const update = { $pull: { stockReservations: intentId } };
  if (finiteLines.length > 0) update.$inc = increments;

  return { filter, update, arrayFilters };
}

/**
 * Clearing the marker once an order exists.
 *
 * A finalized reservation is permanent, so the quantity is NOT given back -
 * only the outstanding-reservation marker is removed, which also keeps the set
 * bounded to checkouts that are actually in flight.
 */
export function buildReservationSettlement({ businessId, intentId }) {
  return {
    filter: { _id: businessId, stockReservations: intentId },
    update: { $pull: { stockReservations: intentId } }
  };
}
