import { Business } from '../models/Business.js';
import { CheckoutIntent } from '../models/CheckoutIntent.js';

import {
  RESERVATION_STATES,
  buildIdentifiedReservation,
  buildReservationFailure,
  isLiveReservationEntry,
  reservationEntryOf
} from '../policies/checkout-intent.policy.js';

/**
 * The durable outcomes recorded in Business.stockReservations.
 *
 * `reserved` and `failed` are immediate per-intent outcomes.
 * `staleFence` is not stored: it means another terminal failure on this
 * Business rotated the permanent generation and this worker must refresh its
 * authority before doing reservation work again.
 */
export const RESERVATION_OUTCOMES = {
  reserved: 'reserved',
  failed: 'failed',
  open: 'open',
  staleFence: 'staleFence'
};

export function normalizedFence(value) {
  return Number.isSafeInteger(value) && value >= 0 ? value : 0;
}

/**
 * Reads both reservation bookkeeping and the current permanent Business fence.
 */
export async function loadReservationContext({
  businessId,
  intentId
}) {
  const business = await Business.findById(businessId).select(
    '+stockReservations +reservationFence'
  );

  if (!business) {
    return {
      business: null,
      fence: null,
      outcome: null
    };
  }

  const outcome = reservationEntryOf(business, intentId);

  return {
    business,
    fence: normalizedFence(business.reservationFence),
    outcome
  };
}

/**
 * Executes one already-authorized reservation attempt.
 *
 * The reservation write itself checks the permanent Business generation.
 * Therefore a worker that becomes stale before this write cannot decrement
 * inventory and discover the loss afterwards: Mongo simply matches nothing.
 */
export async function attemptReservation({
  businessId,
  intentId,
  lines,
  reservationFence
}) {
  const reservation = buildIdentifiedReservation({
    businessId,
    intentId,
    lines,
    reservationFence
  });

  const result = await Business.updateOne(
    reservation.filter,
    reservation.update,
    reservation.arrayFilters.length > 0
      ? { arrayFilters: reservation.arrayFilters }
      : undefined
  );

  return {
    matched: result.matchedCount > 0
  };
}

/**
 * Reads the one Business-side outcome already recorded for this intent.
 */
export async function reservationOutcome({
  businessId,
  intentId
}) {
  const context = await loadReservationContext({
    businessId,
    intentId
  });

  const entry = context.outcome;

  if (!entry) {
    return {
      state: RESERVATION_OUTCOMES.open,
      entry: null,
      fence: context.fence
    };
  }

  if (isLiveReservationEntry(entry)) {
    return {
      state: RESERVATION_OUTCOMES.reserved,
      entry,
      fence: context.fence,
      lines: (entry.lines ?? []).map((line) => ({
        productId: line.productId,
        ...(line.variantId
          ? { variantId: line.variantId }
          : {}),
        quantity: line.quantity
      }))
    };
  }

  return {
    state: RESERVATION_OUTCOMES.failed,
    entry,
    fence: context.fence,
    failureCode: entry.failureCode ?? null
  };
}

/**
 * Competes atomically with a successful reservation.
 *
 * If this succeeds it:
 *   1. records this intent's temporary failed outcome; and
 *   2. permanently rotates the Business generation.
 *
 * Both happen in one Business update.
 */
export async function claimReservationFailure({
  businessId,
  intentId,
  failureCode,
  reservationFence
}) {
  const failure = buildReservationFailure({
    businessId,
    intentId,
    failureCode,
    reservationFence
  });

  const result = await Business.updateOne(
    failure.filter,
    failure.update
  );

  return {
    owned: result.matchedCount > 0
  };
}

/**
 * Resolves a terminal reservation failure without confusing:
 *
 * - another worker's successful reservation,
 * - an already-recorded failure, and
 * - an unrelated Business fence rotation.
 */
export async function resolveReservationFailure({
  businessId,
  intentId,
  failureCode,
  reservationFence
}) {
  const expectedFence = normalizedFence(reservationFence);

  const claimed = await claimReservationFailure({
    businessId,
    intentId,
    failureCode,
    reservationFence: expectedFence
  });

  if (claimed.owned) {
    return {
      owned: true,
      converge: null,
      reservationFence: expectedFence
    };
  }

  const settled = await reservationOutcome({
    businessId,
    intentId
  });

  if (settled.state === RESERVATION_OUTCOMES.reserved) {
    return {
      owned: false,
      converge: RESERVATION_OUTCOMES.reserved,
      lines: settled.lines
    };
  }

  if (settled.state === RESERVATION_OUTCOMES.failed) {
    return {
      owned: false,
      converge: RESERVATION_OUTCOMES.failed,
      failureCode: settled.failureCode ?? failureCode
    };
  }

  if (
    settled.fence !== null &&
    normalizedFence(settled.fence) !== expectedFence
  ) {
    return {
      owned: false,
      converge: RESERVATION_OUTCOMES.staleFence,
      fence: normalizedFence(settled.fence)
    };
  }

  return {
    owned: false,
    converge: RESERVATION_OUTCOMES.open
  };
}

/**
 * Removes only this intent's temporary refusal bookkeeping.
 *
 * IMPORTANT:
 * reservationFence is deliberately NOT moved backwards here.
 */
export async function withdrawReservationFailure({
  businessId,
  intentId
}) {
  await Business.updateOne(
    { _id: businessId },
    {
      $pull: {
        stockReservations: {
          intent: intentId,
          state: RESERVATION_STATES.failed
        }
      }
    }
  );
}

export async function holdsLiveReservation({
  businessId,
  intentId
}) {
  const outcome = await reservationOutcome({
    businessId,
    intentId
  });

  return outcome.state === RESERVATION_OUTCOMES.reserved;
}

/**
 * Gives a still-prepared CheckoutIntent the newest Business generation.
 *
 * `$max` is intentional: two concurrent refreshers can never move the intent
 * generation backwards.
 *
 * A released/releasing/finalizing/finalized checkout cannot refresh authority.
 */
export async function refreshReservationAuthority({
  intentId,
  businessId
}) {
  const context = await loadReservationContext({
    businessId,
    intentId
  });

  if (!context.business) {
    return {
      owned: false,
      reason: 'BUSINESS_NOT_FOUND'
    };
  }

  // Someone already made a durable decision for this exact intent.
  if (context.outcome) {
    return {
      owned: false,
      converge: isLiveReservationEntry(context.outcome)
        ? RESERVATION_OUTCOMES.reserved
        : RESERVATION_OUTCOMES.failed,
      outcome: context.outcome,
      failureCode: context.outcome.failureCode ?? null
    };
  }

  const intent = await CheckoutIntent.findOneAndUpdate(
    {
      _id: intentId,
      phase: 'prepared'
    },
    {
      $max: {
        reservationFence: context.fence
      }
    },
    {
      new: true
    }
  );

  if (!intent) {
    return {
      owned: false,
      reason: 'CHECKOUT_NOT_RESERVABLE'
    };
  }

  return {
    owned: true,
    fence: normalizedFence(intent.reservationFence),
    intent
  };
}

export { RESERVATION_STATES };