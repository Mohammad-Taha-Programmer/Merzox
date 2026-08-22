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

/**
 * The phases from which a worker may still claim the right to act, and the
 * claims themselves.
 *
 * Finalization and release are mutually exclusive DATABASE decisions, not
 * intentions checked earlier: whoever flips the phase owns the outcome, and the
 * loser sees a matched count of zero and stops. Without this a reconciler could
 * read "no order yet", a request could then create one, and the reconciler
 * would refund inventory that a durable order owns.
 */
export const CLAIMABLE_PHASES = ['prepared', 'reserved'];

/** A dead finalizer's claim may be taken over, but only once it is stale. */
export const RECLAIMABLE_PHASES = ['prepared', 'reserved', 'finalizing', 'releasing'];

export const CHECKOUT_CLAIMS = {
  finalizing: 'finalizing',
  releasing: 'releasing'
};

export const CLAIM_ERRORS = {
  /** Another worker owns this checkout's outcome. Stable and retriable. */
  lost: 'CHECKOUT_CLAIM_LOST'
};

export const INVENTORY_ERRORS = {
  /**
   * A merchant tried to rewrite stock while a checkout still holds some of it.
   * Refused rather than merged: the outstanding reservation will be released or
   * settled within the lease above, and the edit succeeds on retry.
   */
  reserved: 'PRODUCT_INVENTORY_RESERVED',

  /**
   * The atomic write missed because the inventory it was computed from is no
   * longer current - another merchant edit landed first, or a checkout
   * finalized and settled. Materially different from `reserved`: nothing is
   * holding stock, the merchant is simply looking at a stale number and needs
   * to reload before deciding again.
   *
   * Deliberately NOT retried on their behalf: they chose a figure from the
   * state they saw, and silently re-applying it against different state could
   * overwrite somebody else's legitimate change.
   */
  changed: 'PRODUCT_INVENTORY_CHANGED'
};

/**
 * Why an atomic inventory write matched nothing.
 *
 * Every predicate in `buildAtomicInventoryUpdate` can be the reason, and they
 * are NOT interchangeable: "a checkout is holding stock" and "your number is
 * stale" ask the merchant to do different things. This decides between them
 * from a fresh read, and is deliberately pure so the decision is testable
 * without a database.
 *
 * It is classification only. It authorizes nothing and performs no write.
 */
export const INVENTORY_CONFLICTS = {
  businessMissing: 'businessMissing',
  businessInactive: 'businessInactive',
  productMissing: 'productMissing',
  reserved: 'reserved',
  stockChanged: 'stockChanged'
};

/**
 * The HTTP answer for each conflict.
 *
 * Kept beside the classifier so the controller and its tests cannot drift: a
 * test that exercised the classifier but hand-wrote the mapping would pass
 * while the API said something else entirely.
 */
export function inventoryConflictResponse(conflict) {
  switch (conflict) {
    case INVENTORY_CONFLICTS.businessMissing:
      return {
        status: 404,
        code: 'BUSINESS_PROFILE_NOT_FOUND',
        message: 'Business profile was not found'
      };
    case INVENTORY_CONFLICTS.businessInactive:
      return {
        status: 403,
        code: 'BUSINESS_ACCOUNT_DISABLED',
        message: 'Business account is disabled'
      };
    case INVENTORY_CONFLICTS.productMissing:
      return { status: 404, code: 'PRODUCT_NOT_FOUND', message: 'Product not found' };
    case INVENTORY_CONFLICTS.reserved:
      return {
        status: 409,
        code: INVENTORY_ERRORS.reserved,
        message:
          'This product has stock reserved by a checkout in progress, please retry shortly'
      };
    default:
      return {
        status: 409,
        code: INVENTORY_ERRORS.changed,
        message:
          'This product inventory changed while the update was in progress, please reload and try again'
      };
  }
}

export function classifyInventoryConflict({
  business,
  product,
  observedStock
}) {
  if (!business) return INVENTORY_CONFLICTS.businessMissing;
  if (!business.isActive) return INVENTORY_CONFLICTS.businessInactive;
  if (!product) return INVENTORY_CONFLICTS.productMissing;

  // Checked before the stock pair: an outstanding reservation is the more
  // actionable answer ("wait a moment"), and a settled one always moves the
  // pair too, so it would be reported as a change anyway.
  if ((business.stockReservations ?? []).length > 0) {
    return INVENTORY_CONFLICTS.reserved;
  }

  // Anything else the filter could have missed on is, by elimination, the
  // compare-and-set: the observed pair is no longer what is stored. Reported as
  // a change rather than as a reservation that demonstrably does not exist.
  return INVENTORY_CONFLICTS.stockChanged;
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
 * The merchant inventory write, as ONE atomic decision.
 *
 * A read that observes "no reservation outstanding" is worthless by the time a
 * later save runs: a checkout can reserve in between, and the save would then
 * overwrite a decremented quantity with a figure computed from stale data. So
 * the reservation-absence predicate is not a pre-check at all - it is part of
 * the same update's filter, and MongoDB evaluates it at write time.
 *
 * Two predicates carry the guarantee:
 *
 *   1. `stockReservations.0` must not exist. The array holds OUTSTANDING
 *      reservations only, so an empty array (or an absent field on a legacy
 *      document) means no checkout is holding stock right now. This is a
 *      business-wide lock, which is deliberately blunter than a per-product one
 *      and correspondingly harder to get wrong.
 *   2. the stock pair must still be what the caller observed. `normalizeStock`
 *      may derive one half of the pair from the current value, so the write
 *      only applies if that current value has not moved underneath it.
 *
 * Every field the merchant is allowed to change is applied in the same update,
 * which is what makes a mixed payload all-or-nothing: if the filter misses,
 * nothing is written - not the stock, and not the description alongside it.
 */
export function buildAtomicInventoryUpdate({
  businessId,
  ownerId,
  productId,
  write,
  observedStock
}) {
  const productMatch = { _id: productId };

  // Compare-and-set, asserting only what actually carries meaning.
  //
  // The observation comes from a Mongoose-loaded product, which applies schema
  // defaults. A pre-inventory document stores no `unlimitedStock` at all, yet
  // reads back as `true` - so asserting `unlimitedStock: true` would compare
  // against a field that is absent on disk and refuse every edit to a legacy
  // product forever.
  //
  // The split mirrors `isFiniteStockProduct`:
  //
  //   observed finite  -> the product must still be finite AND still hold the
  //                       same quantity; this is the case a concurrent edit or
  //                       a settled checkout must be caught by.
  //   observed unlimited -> only the mode is asserted, with the same `$ne:false`
  //                       semantics used elsewhere, because a quantity is
  //                       meaningless while unlimited and may not be stored.
  const observedFinite = observedStock?.unlimitedStock === false;

  if (observedFinite) {
    productMatch.unlimitedStock = false;
    if (observedStock.stockQuantity !== undefined) {
      productMatch.stockQuantity = observedStock.stockQuantity;
    }
  } else if (observedStock?.unlimitedStock !== undefined) {
    productMatch.unlimitedStock = { $ne: false };
  }

  const filter = {
    _id: businessId,
    // Ownership stays part of the write itself, never inferred from a body.
    owner: ownerId,
    isActive: true,
    // The whole point: evaluated by MongoDB at write time, not by us earlier.
    'stockReservations.0': { $exists: false },
    products: { $elemMatch: productMatch }
  };

  const set = {};
  for (const [field, value] of Object.entries(write)) {
    set[`products.$[product].${field}`] = value;
  }

  return {
    filter,
    update: { $set: set },
    arrayFilters: [{ 'product._id': productId }],
    guardsReservation: true
  };
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
/**
 * The consumption an outstanding reservation is holding.
 *
 * Only finite lines ever take stock, so only they are recorded. This travels
 * INSIDE the reservation marker, in the same atomic Business update as the
 * decrement, which is what makes it recoverable: there is no window in which
 * inventory is consumed but the record of what it consumed lives in another
 * document that may never have been written.
 */
export function reservationEntryFor({ intentId, lines }) {
  return {
    intent: intentId,
    lines: lines
      .filter((line) => line.finite)
      .map((line) => ({
        productId: line.product?._id ?? line.productId,
        quantity: line.quantity
      }))
  };
}

export function buildIdentifiedReservation({ businessId, intentId, lines }) {
  const finiteLines = lines.filter((line) => line.finite);

  const filter = {
    _id: businessId,
    isActive: true,
    // Never twice for the same intent.
    'stockReservations.intent': { $ne: intentId },
    $and: lines.map((line) => ({
      products: {
        $elemMatch: {
          _id: line.product?._id ?? line.productId,
          isActive: true,
          // The stock-mode assertion is symmetric on purpose. A finite line
          // must still be finite AND still have the units; a non-finite line
          // must still be non-finite. Without the second half a checkout that
          // read the product as unlimited could reserve after a merchant made
          // it finite, taking the order without consuming the new inventory.
          //
          // `$ne: false` is exactly the negation of `isFiniteStockProduct`:
          // it matches `true`, a missing field and `null` - the legacy shapes
          // this project treats as unlimited - and rejects only explicit
          // `false`. Verified against a real server for all four shapes.
          ...(line.finite
            ? { unlimitedStock: false, stockQuantity: { $gte: line.quantity } }
            : { unlimitedStock: { $ne: false } })
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

  // The marker carries what it consumed, written in the SAME update as the
  // decrement. Recovery therefore never has to trust metadata from a later
  // cross-collection write that may not have happened.
  const update = {
    $push: { stockReservations: reservationEntryFor({ intentId, lines }) }
  };
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
    'stockReservations.intent': intentId
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

  const update = { $pull: { stockReservations: { intent: intentId } } };
  if (finiteLines.length > 0) update.$inc = increments;

  return { filter, update, arrayFilters };
}

/**
 * The lines an outstanding marker says it consumed.
 *
 * This is the authoritative source for compensation. It is read from the
 * Business document itself, so it cannot disagree with the decrement it was
 * written beside. `finite: true` because only finite lines are ever recorded.
 */
export function reservedLinesFromMarker(business, intentId) {
  const entry = (business?.stockReservations ?? []).find(
    (marker) => String(marker.intent) === String(intentId)
  );

  if (!entry) return null;

  return (entry.lines ?? []).map((line) => ({
    productId: line.productId,
    quantity: line.quantity,
    finite: true
  }));
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
    filter: { _id: businessId, 'stockReservations.intent': intentId },
    update: { $pull: { stockReservations: { intent: intentId } } }
  };
}
