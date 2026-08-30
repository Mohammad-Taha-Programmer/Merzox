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

/** Every non-terminal phase, i.e. everything a sweep still has work to do on. */
export const RECLAIMABLE_PHASES = ['prepared', 'reserved', 'finalizing', 'releasing'];

/**
 * The phases from which a checkout may still become `finalized`.
 *
 * `releasing` is deliberately absent. The checkout decision is MONOTONIC: once
 * release owns the outcome no order may be adopted for it, just as once
 * finalization owns the outcome no refund may happen. A stale claim may be
 * CONTINUED by another worker in the same direction; it may never be reversed,
 * because a paused finalizer whose stock was refunded could still land a
 * durable order and die before undoing it.
 */
export const FINALIZABLE_PHASES = ['prepared', 'reserved', 'finalizing'];

/**
 * The legal phase transitions, stated once so a test can hold the code to them.
 *
 * Terminal phases have no outgoing edges at all.
 */
export const CHECKOUT_TRANSITIONS = Object.freeze({
  prepared: ['reserved', 'finalizing', 'releasing', 'released'],
  reserved: ['finalizing', 'releasing'],
  finalizing: ['finalizing', 'finalized'],
  releasing: ['releasing', 'released'],
  finalized: [],
  released: []
});

export function isLegalTransition(from, to) {
  return (CHECKOUT_TRANSITIONS[from] ?? []).includes(to);
}

/**
 * What a Business-side reservation entry asserts, and how it may change.
 *
 * This is INTERNAL inventory bookkeeping. It is not a checkout phase and it is
 * emphatically not a public order status: nothing here ever reaches a customer
 * or a merchant.
 *
 * The two states are the two mutually exclusive outcomes of one checkout's
 * reservation attempt:
 *
 *   reserved - stock was decremented for this intent, and the entry records
 *              exactly what was taken so compensation cannot guess.
 *   failed   - the reservation was refused terminally. The entry holds no
 *              stock; it exists so the refusal is DURABLE and so any later
 *              reservation write for the same intent matches nothing.
 *
 * Neither state may become the other. A checkout that reserved cannot retro-
 * actively fail, and one that failed cannot retroactively reserve - the whole
 * point of putting both in the same array is that the first `$push` wins.
 */
export const RESERVATION_STATES = Object.freeze({
  reserved: 'reserved',
  failed: 'failed'
});

export const RESERVATION_STATES_LIST = Object.freeze([
  RESERVATION_STATES.reserved,
  RESERVATION_STATES.failed
]);

/** No edges at all: an entry is created in its final state, or removed. */
export const RESERVATION_TRANSITIONS = Object.freeze({
  reserved: [],
  failed: []
});

export function isLegalReservationTransition(from, to) {
  return (RESERVATION_TRANSITIONS[from] ?? []).includes(to);
}

/**
 * Whether an entry is holding stock.
 *
 * A missing `state` means `reserved`: entries written before the field existed
 * only ever recorded live reservations, so the negation is on `failed` rather
 * than an equality on `reserved`. Same shape as the `$ne: false` used for
 * legacy `unlimitedStock`, and proven against a real server the same way.
 */
export function isLiveReservationEntry(entry) {
  return Boolean(entry) && entry.state !== RESERVATION_STATES.failed;
}

/** The `$elemMatch` that selects only entries actually holding stock. */
export const LIVE_RESERVATION_MATCH = Object.freeze({
  state: { $ne: RESERVATION_STATES.failed }
});

/** Businesses with at least one entry holding stock. Legacy-safe. */
export const HOLDS_LIVE_RESERVATION = Object.freeze({
  stockReservations: { $elemMatch: LIVE_RESERVATION_MATCH }
});

/**
 * The terminal reservation failure, as ONE atomic decision.
 *
 * A worker may not conclude "the stock is not there" from an earlier read: a
 * concurrent worker on the same checkout can reserve between that read and the
 * `released` write, leaving a released intent standing against a live
 * reservation and permanently consumed stock. So the refusal is not a
 * conclusion at all - it is a conditional write that competes for the SAME
 * predicate the reservation competes for:
 *
 *   'stockReservations.intent': { $ne: intentId }
 *
 * Exactly one of the two `$push`es can match. Whoever lands first owns the
 * checkout's reservation outcome, and the loser is told so by a matched count
 * of zero - not by a later observation it might never make.
 *
 * The entry holds no lines, so it can never be mistaken for consumption.
 */

export function buildReservationFailure({
  businessId,
  intentId,
  failureCode,
  reservationFence
}) {
  return {
    filter: {
      _id: businessId,
      'stockReservations.intent': { $ne: intentId },

      // Reservation success and terminal failure must compete under the exact
      // same Business generation. If another failure already rotated the
      // generation, this worker no longer owns reservation authority.
      ...reservationFenceClause(reservationFence)
    },

    update: {
      $push: {
        stockReservations: {
          intent: intentId,
          state: RESERVATION_STATES.failed,
          failureCode,
          lines: []
        }
      },

      // Permanent fencing. The temporary failed entry may later be deleted,
      // but every worker carrying the previous generation stays invalid.
      $inc: {
        reservationFence: 1
      }
    }
  };
}

/** The entry recorded for this intent, whatever it asserts. */
export function reservationEntryOf(business, intentId) {
  return (
    (business?.stockReservations ?? []).find(
      (entry) => String(entry.intent) === String(intentId)
    ) ?? null
  );
}

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
  if ((business.stockReservations ?? []).some(isLiveReservationEntry)) {
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
  paymentMethod,
  deliveryOption
}) {
  const tier = String(deliveryOption ?? '').trim();

  return {
    businessId: String(businessId ?? '').trim(),

    // Absent for the standard tier, which is what every order was before the
    // choice existed. Fingerprints written then stay byte-identical, so a
    // retry spanning this change still finds its own intent.
    ...(tier && tier !== 'standard' ? { deliveryOption: tier } : {}),

    // `normalizeRequestedItems` has already merged identical sellable
    // identities. A simple-product item deliberately keeps the historical
    // `{productId, quantity}` shape so fingerprints written before variants
    // existed remain retry-compatible.
    items: [...(items ?? [])]
      .map((item) => {
        const productId = String(item.productId ?? '').trim();
        const rawVariantId = item.variantId;
        const variantId =
          rawVariantId === undefined ||
          rawVariantId === null ||
          String(rawVariantId).trim().length === 0
            ? null
            : String(rawVariantId).trim();

        return {
          productId,
          ...(variantId ? { variantId } : {}),
          quantity: Number(item.quantity)
        };
      })
      .sort((left, right) => {
        const productOrder =
          left.productId.localeCompare(right.productId);

        if (productOrder !== 0) return productOrder;

        return String(left.variantId ?? '').localeCompare(
          String(right.variantId ?? '')
        );
      }),
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
 * Converts one already-observed variant into the exact state that matters to
 * a merchant replacement write.
 *
 * This is deliberately not a public serializer. It exists only so MongoDB can
 * reject a stale full-array variant replacement instead of allowing the last
 * merchant write to erase a concurrent one.
 */
function variantCasSnapshot(variant) {
  const identity = variant?._id ?? variant?.id;

  return {
    ...(identity ? { _id: identity } : {}),
    label: String(variant?.label ?? '').trim(),
    priceOverride: variant?.priceOverride ?? null,
    costPrice: variant?.costPrice ?? null,
    stockQuantity: variant?.stockQuantity ?? 0,
    unlimitedStock: variant?.unlimitedStock ?? true,
    isActive: variant?.isActive ?? true
  };
}

/**
 * Adds a compare-and-set assertion for the complete observed variant set.
 *
 * Empty is special: legacy/simple products may physically omit `variants`, so
 * `variants.0 does not exist` accepts both missing and empty arrays.
 *
 * Non-empty arrays are matched by size plus one identity/state elemMatch for
 * every observed variant. Variant ids are unique, so this proves the exact
 * observed set still exists without relying on BSON embedded-document field
 * order.
 */
function guardObservedVariants(productMatch, observedVariants) {
  if (observedVariants === undefined) return;

  const observed = [...(observedVariants ?? [])];

  if (observed.length === 0) {
    productMatch['variants.0'] = { $exists: false };
    return;
  }

  productMatch.variants = {
    $size: observed.length,
    $all: observed.map((variant) => ({
      $elemMatch: variantCasSnapshot(variant)
    }))
  };
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
 *   1. no entry may be HOLDING stock. The array carries outstanding
 *      reservations and terminal-failure records; only the former hold
 *      anything, so the predicate is `$not: $elemMatch: {state: {$ne:
 *      'failed'}}` - which an empty array, an absent field on a legacy
 *      document, and an array of pure failure records all satisfy. This is a
 *      business-wide lock, deliberately blunter than a per-product one and
 *      correspondingly harder to get wrong.
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
  observedStock,
  observedVariants
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

  // A variant PATCH replaces the array. Assert the exact array the merchant
  // write was derived from so two stale variant edits can never both apply.
  guardObservedVariants(productMatch, observedVariants);

  const filter = {
    _id: businessId,
    // Ownership stays part of the write itself, never inferred from a body.
    owner: ownerId,
    isActive: true,
    // The whole point: evaluated by MongoDB at write time, not by us earlier.
    // Only entries HOLDING stock block a merchant edit; a `failed` entry is a
    // record that a checkout was refused and holds nothing, so it must not
    // freeze the merchant's inventory until it is swept.
    stockReservations: { $not: { $elemMatch: LIVE_RESERVATION_MATCH } },
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
 * Only finite lines ever take stock, so only they are recorded. Variant
 * identity travels inside the marker in the same Business-document atomic
 * update as its decrement.
 */
function reservationProductId(line) {
  return line.product?._id ?? line.productId;
}

function reservationVariantId(line) {
  return line.variant?._id ?? line.variantId ?? null;
}

function reservationStockCriteria(line) {
  return line.finite
    ? {
        unlimitedStock: false,
        stockQuantity: { $gte: line.quantity }
      }
    : {
        unlimitedStock: { $ne: false }
      };
}

/**
 * The exact catalog identity that must still exist at reservation time.
 *
 * Simple products assert that they are STILL simple. This closes the race where
 * a merchant could add variants after checkout resolution but before the
 * reservation write, which would otherwise let the stale checkout consume the
 * now-irrelevant parent stock.
 */
function reservationProductCriteria(line) {
  const productId = reservationProductId(line);
  const variantId = reservationVariantId(line);

  if (variantId) {
    return {
      _id: productId,
      isActive: true,
      variants: {
        $elemMatch: {
          _id: variantId,
          isActive: true,
          ...reservationStockCriteria(line)
        }
      }
    };
  }

  return {
    _id: productId,
    isActive: true,
    // Missing and empty variant arrays both satisfy this.
    'variants.0': { $exists: false },
    ...reservationStockCriteria(line)
  };
}

/**
 * Builds the exact finite inventory path and its array filters.
 *
 * Existing simple-product aliases stay `lineN`, preserving the historical
 * builder shape. Variant lines add one nested `variantN` identity.
 */
function finiteStockTarget(line, index, { reserve }) {
  const productId = reservationProductId(line);
  const variantId = reservationVariantId(line);
  const productAlias = `line${index}`;

  if (variantId) {
    const variantAlias = `variant${index}`;

    return {
      path:
        `products.$[${productAlias}].variants.$[${variantAlias}].stockQuantity`,
      arrayFilters: [
        {
          [`${productAlias}._id`]: productId
        },
        {
          [`${variantAlias}._id`]: variantId,
          [`${variantAlias}.unlimitedStock`]: false,
          ...(reserve
            ? {
                [`${variantAlias}.isActive`]: true,
                [`${variantAlias}.stockQuantity`]: {
                  $gte: line.quantity
                }
              }
            : {})
        }
      ]
    };
  }

  return {
    path: `products.$[${productAlias}].stockQuantity`,
    arrayFilters: [
      {
        [`${productAlias}._id`]: productId,
        [`${productAlias}.unlimitedStock`]: false,
        ...(reserve
          ? {
              [`${productAlias}.stockQuantity`]: {
                $gte: line.quantity
              }
            }
          : {})
      }
    ]
  };
}

export function reservationEntryFor({ intentId, lines }) {
  return {
    intent: intentId,
    state: RESERVATION_STATES.reserved,
    lines: lines
      .filter((line) => line.finite)
      .map((line) => {
        const variantId = reservationVariantId(line);

        return {
          productId: reservationProductId(line),
          ...(variantId ? { variantId } : {}),
          quantity: line.quantity
        };
      })
  };
}

export function buildIdentifiedReservation({
  businessId,
  intentId,
  lines,
  reservationFence
}) {
  const finiteLines = lines.filter((line) => line.finite);

  const filter = {
    _id: businessId,
    isActive: true,

    // Never twice for the same checkout intent.
    'stockReservations.intent': { $ne: intentId },

    // Permanent fencing.
    ...reservationFenceClause(reservationFence),

    // Every requested sellable identity must still have the same stock mode
    // and enough quantity when MongoDB evaluates this write.
    $and: lines.map((line) => ({
      products: {
        $elemMatch: reservationProductCriteria(line)
      }
    }))
  };

  const increments = {};
  const arrayFilters = [];

  finiteLines.forEach((line, index) => {
    const target = finiteStockTarget(line, index, {
      reserve: true
    });

    increments[target.path] = -line.quantity;
    arrayFilters.push(...target.arrayFilters);
  });

  // Marker + every finite decrement are one Business-document atomic fact.
  const update = {
    $push: {
      stockReservations: reservationEntryFor({
        intentId,
        lines
      })
    }
  };

  if (finiteLines.length > 0) {
    update.$inc = increments;
  }

  return {
    filter,
    update,
    arrayFilters
  };
}

/**
 * The compensating release, guarded by the same identity.
 *
 * A variant reservation is returned only to that exact variant. If the
 * inventory target was removed or changed to unlimited outside the supported
 * merchant path, its quantity is not invented somewhere else: the marker is
 * still retired, matching the existing simple-product safety rule.
 */
export function buildIdentifiedRelease({ businessId, intentId, lines }) {
  const finiteLines = lines.filter((line) => line.finite);

  const filter = {
    _id: businessId,
    // Only a reservation that is still outstanding can be released.
    'stockReservations.intent': intentId
  };

  const increments = {};
  const arrayFilters = [];

  finiteLines.forEach((line, index) => {
    const target = finiteStockTarget(line, index, {
      reserve: false
    });

    increments[target.path] = line.quantity;
    arrayFilters.push(...target.arrayFilters);
  });

  const update = {
    $pull: {
      stockReservations: {
        intent: intentId
      }
    }
  };

  if (finiteLines.length > 0) {
    update.$inc = increments;
  }

  return {
    filter,
    update,
    arrayFilters
  };
}

/**
 * The lines an outstanding marker says it consumed.
 *
 * This is the authoritative source for compensation. It is read from the
 * Business document itself, so it cannot disagree with the decrement it was
 * written beside. `finite: true` because only finite lines are ever recorded.
 */
export function reservedLinesFromMarker(business, intentId) {
  const entry = reservationEntryOf(business, intentId);

  // A `failed` entry is a durable refusal, not consumption. Treating it as a
  // reservation would invent stock to give back.
  if (!isLiveReservationEntry(entry)) return null;

  return (entry.lines ?? []).map((line) => ({
    productId: line.productId,
    ...(line.variantId
      ? { variantId: line.variantId }
      : {}),
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

export function reservationFenceClause(value) {
  const fence =
    Number.isSafeInteger(value) && value >= 0
      ? value
      : 0;

  if (fence === 0) {
    return {
      $or: [
        { reservationFence: 0 },
        { reservationFence: { $exists: false } }
      ]
    };
  }

  return { reservationFence: fence };
}