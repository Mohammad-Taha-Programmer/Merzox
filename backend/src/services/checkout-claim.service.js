import { CheckoutIntent } from '../models/CheckoutIntent.js';
import {
  CHECKOUT_STALE_LEASE_MS,
  CLAIMABLE_PHASES,
  CHECKOUT_CLAIMS
} from '../policies/checkout-intent.policy.js';

/**
 * Exclusive ownership of a checkout's outcome.
 *
 * Finalization and release are mutually exclusive, and the exclusion is a
 * conditional database write rather than a check somebody performed earlier:
 * whoever flips the phase owns the result, and the loser is told so by the
 * absence of a matched document. Both claims live here so the request path and
 * the reconciler cannot drift into different rules.
 */

const TAKEOVER_PHASES = [CHECKOUT_CLAIMS.finalizing, CHECKOUT_CLAIMS.releasing];

/**
 * The filter a claim is allowed to match.
 *
 * An unfinished checkout is always claimable. A checkout somebody else has
 * already claimed may only be taken over once it has gone quiet for longer than
 * the abandonment lease - a live worker is never robbed mid-flight.
 */
export function claimableFilter({ intentId, now, staleAfterMs = CHECKOUT_STALE_LEASE_MS }) {
  return {
    _id: intentId,
    $or: [
      { phase: { $in: CLAIMABLE_PHASES } },
      {
        phase: { $in: TAKEOVER_PHASES },
        updatedAt: { $lte: new Date(now - staleAfterMs) }
      }
    ]
  };
}

/**
 * Claims the right to write this checkout's order.
 *
 * Returns the claimed intent, or null when another actor owns the outcome. A
 * null result must never be treated as permission: no order may be created
 * without it.
 */
export function claimFinalization({ intentId, now = Date.now(), staleAfterMs }) {
  return CheckoutIntent.findOneAndUpdate(
    claimableFilter({ intentId, now, staleAfterMs }),
    { $set: { phase: CHECKOUT_CLAIMS.finalizing } },
    { new: true }
  );
}

/**
 * Claims the right to give this reservation back.
 *
 * The mirror of the above. Once acquired, no order may be created for the
 * checkout; if it cannot be acquired, no inventory may be touched.
 */
export function claimRelease({ intentId, now = Date.now(), staleAfterMs }) {
  return CheckoutIntent.findOneAndUpdate(
    claimableFilter({ intentId, now, staleAfterMs }),
    { $set: { phase: CHECKOUT_CLAIMS.releasing } },
    { new: true }
  );
}

/**
 * Confirms that this worker still owned the checkout when its order landed.
 *
 * Conditional on the finalization claim still standing. A worker that stalled
 * past the lease can find its claim taken over, and it must not report success
 * for an order whose inventory somebody else already gave back - so the caller
 * is told plainly whether it still owns the outcome.
 */
export async function confirmFinalization({ intentId, orderId }) {
  const result = await CheckoutIntent.updateOne(
    { _id: intentId, phase: CHECKOUT_CLAIMS.finalizing },
    { $set: { phase: 'finalized', order: orderId, failureCode: null } }
  );

  return { owned: result.matchedCount > 0 };
}
