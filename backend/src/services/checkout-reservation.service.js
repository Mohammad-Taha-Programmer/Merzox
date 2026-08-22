import { Business } from '../models/Business.js';
import {
  RESERVATION_STATES,
  buildIdentifiedReservation,
  buildReservationFailure,
  isLiveReservationEntry,
  reservationEntryOf
} from '../policies/checkout-intent.policy.js';

/**
 * Exclusive ownership of one checkout's RESERVATION outcome.
 *
 * A checkout's reservation can end two ways, and they are mutually exclusive
 * facts about the same inventory: either stock was decremented for this intent,
 * or the reservation was refused terminally. R7 made the finalize/release
 * decision monotonic; this makes the decision BEFORE it exclusive.
 *
 * The hazard it closes is a read-check-write. A worker used to conclude "the
 * stock is not there" from an earlier `Business.exists` and then write
 * `released` several operations later. A second worker on the same key - one
 * that took the checkout over after the convergence timeout - could reserve
 * inside that gap, leaving a released intent standing against a live
 * reservation and permanently consumed stock that no sweep would ever inspect.
 *
 * The fix is not another check. Both outcomes are a `$push` into
 * `stockReservations` guarded by the SAME predicate:
 *
 *   'stockReservations.intent': { $ne: intentId }
 *
 * so MongoDB's single-document atomicity decides. Exactly one can land, the
 * loser is told by a matched count of zero, and a stale worker that wakes up
 * later finds its reservation write matching nothing because the failure record
 * is already sitting in the array it is guarded against. No lease, no token and
 * no transaction is needed: the array itself is the arbiter.
 *
 * Every function here reports what the database actually did. A caller may
 * never treat a lost claim as permission.
 */

/** What the array says about this checkout, once and for all. */
export const RESERVATION_OUTCOMES = {
  /** Stock is decremented and held for this intent. */
  reserved: 'reserved',
  /** The reservation was refused terminally, durably. */
  failed: 'failed',
  /** Nothing recorded yet: the outcome is still open. */
  open: 'open'
};

/**
 * Attempts the reservation itself.
 *
 * Unchanged in shape from R6/R7 - the decrement and the marker recording what
 * it consumed are still one atomic write - but it is now also fenced by the
 * failure record: if a terminal refusal landed first, this matches nothing.
 */
export async function attemptReservation({ businessId, intentId, lines }) {
  const reservation = buildIdentifiedReservation({
    businessId,
    intentId,
    lines
  });

  const result = await Business.updateOne(
    reservation.filter,
    reservation.update,
    reservation.arrayFilters.length > 0
      ? { arrayFilters: reservation.arrayFilters }
      : undefined
  );

  return { matched: result.matchedCount > 0 };
}

/**
 * Reads the one durable fact that decides this checkout's reservation.
 *
 * A single read of the arbiter, so a caller never has to combine two
 * observations that could disagree.
 */
export async function reservationOutcome({ businessId, intentId }) {
  const holder = await Business.findById(businessId).select(
    '+stockReservations'
  );
  const entry = reservationEntryOf(holder, intentId);

  if (!entry) return { state: RESERVATION_OUTCOMES.open, entry: null };

  if (isLiveReservationEntry(entry)) {
    return {
      state: RESERVATION_OUTCOMES.reserved,
      entry,
      lines: (entry.lines ?? []).map((line) => ({
        productId: line.productId,
        quantity: line.quantity
      }))
    };
  }

  return {
    state: RESERVATION_OUTCOMES.failed,
    entry,
    failureCode: entry.failureCode ?? null
  };
}

/**
 * Claims the right to declare this checkout's reservation terminally failed.
 *
 * This is the whole mutual-exclusion mechanism, and it has to BE the
 * conditional write rather than a decision taken before one. `owned: false`
 * means another worker's outcome is already recorded for this intent - and
 * `released` must not be written, because the recorded outcome may be a live
 * reservation holding real stock.
 */
export async function claimReservationFailure({
  businessId,
  intentId,
  failureCode
}) {
  const failure = buildReservationFailure({
    businessId,
    intentId,
    failureCode
  });

  const result = await Business.updateOne(failure.filter, failure.update);

  return { owned: result.matchedCount > 0 };
}

/**
 * The complete terminal-failure decision for one checkout.
 *
 * The claim and the response to losing it belong together: a caller that takes
 * only the claim could still act as though a lost one were permission. So this
 * returns what the worker is ALLOWED to do, never just what it wanted to do.
 *
 *   { owned: true }                      -> the refusal is durable; release it
 *   { owned: false, converge: 'failed' } -> somebody already refused it
 *   { owned: false, converge: 'reserved' } -> somebody reserved it; sell that
 *
 * The `reserved` case is the race this whole pass exists for: a concurrent
 * worker on the same key reserved between this worker's attempt and its
 * decision. Writing `released` then would strand consumed stock behind a
 * terminally failed checkout.
 */
export async function resolveReservationFailure({
  businessId,
  intentId,
  failureCode
}) {
  const claimed = await claimReservationFailure({
    businessId,
    intentId,
    failureCode
  });

  if (claimed.owned) return { owned: true, converge: null };

  // The push can only fail when an entry already exists, so read the one that
  // beat this worker and obey it.
  const settled = await reservationOutcome({ businessId, intentId });

  if (settled.state === RESERVATION_OUTCOMES.reserved) {
    return { owned: false, converge: RESERVATION_OUTCOMES.reserved, lines: settled.lines };
  }

  if (settled.state === RESERVATION_OUTCOMES.failed) {
    return {
      owned: false,
      converge: RESERVATION_OUTCOMES.failed,
      failureCode: settled.failureCode ?? failureCode
    };
  }

  // Unreachable by construction. Reported as open rather than as a refusal, so
  // an impossible read can never become a false stock error for a customer.
  return { owned: false, converge: RESERVATION_OUTCOMES.open };
}

/**
 * Withdraws this worker's own refusal record.
 *
 * Scoped to the intent AND to `failed`, so it can never remove a live
 * reservation. Used when the checkout left the failable phases while this
 * worker was deciding - the refusal is then simply wrong.
 */
export async function withdrawReservationFailure({ businessId, intentId }) {
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

/** Whether an intent is holding stock right now. Never counts a refusal. */
export async function holdsLiveReservation({ businessId, intentId }) {
  const outcome = await reservationOutcome({ businessId, intentId });

  return outcome.state === RESERVATION_OUTCOMES.reserved;
}

export { RESERVATION_STATES };
