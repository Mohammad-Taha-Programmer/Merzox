import mongoose from 'mongoose';

import { CheckoutIntent } from '../models/CheckoutIntent.js';
import {
  CHECKOUT_STALE_LEASE_MS,
  CLAIMABLE_PHASES,
  CHECKOUT_CLAIMS
} from '../policies/checkout-intent.policy.js';

/**
 * Exclusive, DIRECTIONAL ownership of a checkout's outcome.
 *
 * Finalization and release are mutually exclusive, and the exclusion is a
 * conditional database write rather than a check somebody performed earlier:
 * whoever flips the phase owns the result, and the loser is told so by the
 * absence of a matched document.
 *
 * The rule that makes this safe is MONOTONICITY. The first successful move out
 * of an undecided phase is the checkout's decision, and it is irrevocable:
 *
 *   prepared/reserved -> finalizing -> finalized
 *   prepared/reserved -> releasing  -> released
 *
 * A lease lets ANOTHER WORKER CONTINUE a decision its owner abandoned. It never
 * lets a worker REVERSE one. A stale `finalizing` may only be resumed by
 * another finalizer, and a stale `releasing` only by another releaser -
 * otherwise a paused finalizer could have its stock refunded underneath it and
 * still land a durable order, which no later bookkeeping can undo if the
 * process dies in between.
 *
 * A lease is not fencing, so every claim also mints a `claimToken`. Decisive
 * writes are conditional on it, which is what stops a worker whose claim was
 * taken over from acting on ownership it no longer holds.
 */

/** A fresh, unguessable fencing token. One per acquisition, never reused. */
export function newClaimToken() {
  return new mongoose.Types.ObjectId();
}

function staleBefore(now, staleAfterMs) {
  return new Date(now - staleAfterMs);
}

/**
 * What a FINALIZATION claim may match: an undecided checkout, or a
 * finalization whose owner has gone quiet past the abandonment lease.
 *
 * It can never match `releasing`, `released` or `finalized`. Staleness does not
 * change that - it only decides whether the SAME decision may be resumed.
 */
export function finalizationClaimFilter({
  intentId,
  now = Date.now(),
  staleAfterMs = CHECKOUT_STALE_LEASE_MS
}) {
  return {
    _id: intentId,
    $or: [
      { phase: { $in: CLAIMABLE_PHASES } },
      {
        phase: CHECKOUT_CLAIMS.finalizing,
        updatedAt: { $lte: staleBefore(now, staleAfterMs) }
      }
    ]
  };
}

/**
 * What a RELEASE claim may match: an undecided checkout, or a release whose
 * owner has gone quiet past the abandonment lease.
 *
 * The mirror of the above, and just as strict: it can never match `finalizing`,
 * `finalized` or `released`.
 */
export function releaseClaimFilter({
  intentId,
  now = Date.now(),
  staleAfterMs = CHECKOUT_STALE_LEASE_MS
}) {
  return {
    _id: intentId,
    $or: [
      { phase: { $in: CLAIMABLE_PHASES } },
      {
        phase: CHECKOUT_CLAIMS.releasing,
        updatedAt: { $lte: staleBefore(now, staleAfterMs) }
      }
    ]
  };
}

/**
 * Claims the right to write this checkout's order.
 *
 * Two conditional writes, each atomic on its own, because they mean different
 * things:
 *
 *   1. DECIDING an undecided checkout. The finalization snapshot lands in the
 *      SAME write as the decision, so there is no instant in which the phase
 *      says "an order is being written" while nothing on disk says what that
 *      order is. A caller with no snapshot may not take this step at all.
 *   2. RESUMING a finalization somebody abandoned. The decision and its
 *      snapshot already stand and are never rewritten - only the fencing token
 *      and the lease are refreshed.
 *
 * Returns the claimed intent, or null when another actor owns the outcome. A
 * null result must never be treated as permission: no order may be created
 * without it.
 */
export async function claimFinalization({
  intentId,
  snapshot = null,
  now = Date.now(),
  staleAfterMs = CHECKOUT_STALE_LEASE_MS
}) {
  if (snapshot) {
    const decided = await CheckoutIntent.findOneAndUpdate(
      { _id: intentId, phase: { $in: CLAIMABLE_PHASES } },
      {
        $set: {
          phase: CHECKOUT_CLAIMS.finalizing,
          claimToken: newClaimToken(),
          finalization: snapshot
        }
      },
      { new: true }
    );

    if (decided) return decided;
  }

  return CheckoutIntent.findOneAndUpdate(
    {
      _id: intentId,
      phase: CHECKOUT_CLAIMS.finalizing,
      updatedAt: { $lte: staleBefore(now, staleAfterMs) }
    },
    { $set: { claimToken: newClaimToken() } },
    { new: true }
  );
}

/**
 * Claims the right to give this reservation back.
 *
 * The mirror of the above. Once acquired, no order may be created for the
 * checkout; if it cannot be acquired, no inventory may be touched.
 */
export function claimRelease({
  intentId,
  now = Date.now(),
  staleAfterMs = CHECKOUT_STALE_LEASE_MS
}) {
  return CheckoutIntent.findOneAndUpdate(
    releaseClaimFilter({ intentId, now, staleAfterMs }),
    {
      $set: {
        phase: CHECKOUT_CLAIMS.releasing,
        claimToken: newClaimToken()
      }
    },
    { new: true }
  );
}

/**
 * Confirms that this worker still owned the checkout when its order landed.
 *
 * Conditional on the finalization claim AND on the fencing token, so a worker
 * that stalled past the lease cannot write a result on behalf of the claim that
 * replaced it. Losing here is never dangerous any more: a finalization can only
 * be taken over by another finalizer, so the order is valid either way.
 */
export async function confirmFinalization({ intentId, orderId, claimToken }) {
  const result = await CheckoutIntent.updateOne(
    {
      _id: intentId,
      phase: CHECKOUT_CLAIMS.finalizing,
      ...(claimToken ? { claimToken } : {})
    },
    { $set: { phase: 'finalized', order: orderId, failureCode: null } }
  );

  return { owned: result.matchedCount > 0 };
}

/**
 * Confirms that this worker still owned the checkout when its refund landed.
 *
 * The release mirror of `confirmFinalization`, and fenced the same way.
 */
export async function confirmRelease({ intentId, failureCode, claimToken }) {
  const result = await CheckoutIntent.updateOne(
    {
      _id: intentId,
      phase: CHECKOUT_CLAIMS.releasing,
      ...(claimToken ? { claimToken } : {})
    },
    { $set: { phase: 'released', failureCode } }
  );

  return { owned: result.matchedCount > 0 };
}
