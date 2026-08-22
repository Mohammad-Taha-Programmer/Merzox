import { Business } from '../models/Business.js';
import { CheckoutIntent } from '../models/CheckoutIntent.js';
import { Order } from '../models/Order.js';
import {
  CHECKOUT_CLAIMS,
  CHECKOUT_STALE_LEASE_MS,
  FINALIZABLE_PHASES,
  RECLAIMABLE_PHASES,
  RECONCILE_BATCH_LIMIT,
  RECONCILE_INTERVAL_MS,
  buildIdentifiedRelease,
  buildReservationSettlement,
  reservedLinesFromMarker
} from '../policies/checkout-intent.policy.js';
import {
  claimFinalization,
  claimRelease,
  confirmFinalization,
  confirmRelease
} from './checkout-claim.service.js';
import { safeErrorCode } from '../utils/safe-log.js';

/**
 * Autonomous recovery for checkouts whose client never came back.
 *
 * The per-request state machine can already resume any interrupted checkout,
 * but only when someone retries the same key. A customer whose app was closed
 * mid-checkout never retries, and without this their reservation would hold
 * finite stock indefinitely. This is the process that eventually settles those.
 *
 * Every action is idempotent and phase-conditional, so running it twice - or
 * concurrently with a real request on the same intent - reaches the same state.
 * It never returns stock that belongs to an order.
 *
 * It CONTINUES decisions; it never reverses them. A checkout that already chose
 * finalization is driven to an order using the snapshot frozen at that
 * decision, and one that already chose release is driven to a refund. Reversing
 * either would allow the state this whole design exists to prevent: a durable
 * order standing against stock somebody gave back.
 */

/** Outcomes, so a caller (and a test) can assert what actually happened. */
export const RECONCILE_ACTIONS = {
  finalized: 'finalized',
  released: 'released',
  markerCleaned: 'markerCleaned',
  skipped: 'skipped'
};

/**
 * The lease is deliberately NOT the request-path convergence wait.
 *
 * A duplicate HTTP request waits ~3s because a person is on the other end. A
 * checkout is only presumed dead after a much longer silence, so a slow but
 * genuinely progressing request is never stolen from.
 */
export function isStale(intent, now, staleAfterMs = CHECKOUT_STALE_LEASE_MS) {
  const touched = intent?.updatedAt ?? intent?.createdAt;
  if (!touched) return false;

  return now - new Date(touched).getTime() >= staleAfterMs;
}

async function settleMarker(intent) {
  const settlement = buildReservationSettlement({
    businessId: intent.business,
    intentId: intent._id
  });

  // A pull, never an increment: the stock belongs to the order now.
  await Business.updateOne(settlement.filter, settlement.update);
}

async function finalizeAgainst(intent, order) {
  // A durable order exists, so the only correct outcome is finalized - never a
  // refund. Conditional on a non-terminal phase so a checkout somebody already
  // released is not silently rewritten.
  await CheckoutIntent.updateOne(
    { _id: intent._id, phase: { $in: FINALIZABLE_PHASES } },
    { $set: { phase: 'finalized', order: order._id, failureCode: null } }
  );
  await settleMarker(intent);

  return RECONCILE_ACTIONS.finalized;
}

/**
 * Gives back exactly what the outstanding marker says was consumed.
 *
 * The lines come from the Business document, not from the CheckoutIntent. The
 * marker was written in the same atomic update as the decrement, so it cannot
 * disagree with it; the intent's own copy is written afterwards and a crash in
 * between would leave it stale - describing, for instance, an unlimited line
 * for stock that was actually taken finitely.
 */
async function releaseAndClose(intent, failureCode, staleAfterMs) {
  // A live finalizer is never robbed: its claim can only be taken over once it
  // has gone quiet for longer than the abandonment lease.
  const claimed = await claimRelease({ intentId: intent._id, staleAfterMs });

  if (!claimed) {
    // Finalization owns it, or it is already terminal. Refunding now could
    // strand a durable order against restored stock.
    return RECONCILE_ACTIONS.skipped;
  }

  const holder = await Business.findById(intent.business).select(
    '+stockReservations'
  );
  const reservedLines = reservedLinesFromMarker(holder, intent._id);

  if (reservedLines) {
    const release = buildIdentifiedRelease({
      businessId: intent.business,
      intentId: intent._id,
      lines: reservedLines
    });

    // Guarded by the marker, so a reservation that was already given back - or
    // never taken - cannot be given back a second time.
    await Business.updateOne(
      release.filter,
      release.update,
      release.arrayFilters.length > 0
        ? { arrayFilters: release.arrayFilters }
        : undefined
    );
  }

  await confirmRelease({
    intentId: intent._id,
    failureCode,
    claimToken: claimed.claimToken
  });

  return RECONCILE_ACTIONS.released;
}

/**
 * Finishes a finalization whose worker never came back.
 *
 * The decision to finalize already stands, so the only correct outcome is an
 * order - never a refund. Everything the order needs was frozen into the intent
 * in the same write that made the decision, so nothing here consults the
 * merchant's current catalog: a price or a discount edited since then cannot
 * rewrite what the customer committed to.
 */
async function continueFinalization(intent, staleAfterMs) {
  // No snapshot is passed: this may only RESUME a stale finalization, never
  // decide an undecided checkout. A fresh claim is left to its live owner.
  const claimed = await claimFinalization({ intentId: intent._id, staleAfterMs });

  if (!claimed) return RECONCILE_ACTIONS.skipped;

  const stored = await CheckoutIntent.findById(intent._id).select(
    '+finalization'
  );
  const draft = stored?.finalization?.orderDraft;

  if (!draft) {
    // Nothing to finish from. Refusing is the only safe answer: refunding here
    // is exactly the reversal this pass exists to forbid.
    return RECONCILE_ACTIONS.skipped;
  }

  let order = await Order.findOne({
    user: stored.user,
    clientOrderId: stored.clientOrderId
  });

  if (!order) {
    try {
      order = await Order.create(draft);
    } catch {
      // A concurrent finalizer may have won the unique key. That is
      // convergence, not failure, so adopt its order rather than writing a
      // second one - and if there really is none, leave the decision standing
      // for the next sweep instead of reversing it.
      order = await Order.findOne({
        user: stored.user,
        clientOrderId: stored.clientOrderId
      });
      if (!order) return RECONCILE_ACTIONS.skipped;
    }
  }

  // Losing the token here means another finalizer confirmed first. The order is
  // the same physical order either way, so the marker is still settled - a pull
  // with no increment, which can never give back stock the order owns.
  await confirmFinalization({
    intentId: intent._id,
    orderId: order._id,
    claimToken: claimed.claimToken
  });
  await settleMarker(intent);

  return RECONCILE_ACTIONS.finalized;
}

/**
 * Drives one intent to a terminal, marker-free state.
 *
 * The decision is always "does a durable order exist for this key". If it does
 * the checkout succeeded and only the bookkeeping is missing; if it does not,
 * nothing was sold and the reservation must go back.
 */
export async function reconcileIntent(intent, staleAfterMs = CHECKOUT_STALE_LEASE_MS) {
  if (intent.phase === 'released') {
    // A release already pulled its own marker in the same update, so there is
    // nothing left to do.
    return RECONCILE_ACTIONS.skipped;
  }

  if (intent.phase === 'finalized') {
    // CRASH-FINAL-01: the order is durable and the intent knows it, but the
    // process died before the marker came off. Clean it, restore nothing.
    await settleMarker(intent);
    return RECONCILE_ACTIONS.markerCleaned;
  }

  if (intent.phase === CHECKOUT_CLAIMS.releasing) {
    // The decision is release. It may only be continued, and only once its
    // owner has gone quiet - never turned back into a finalization.
    return releaseAndClose(
      intent,
      intent.failureCode ?? 'CHECKOUT_ABANDONED',
      staleAfterMs
    );
  }

  // A durable order is decisive: if one exists this checkout succeeded, and the
  // only thing missing is bookkeeping. Checked before any release is claimed.
  const order = await Order.findOne({
    user: intent.user,
    clientOrderId: intent.clientOrderId
  });

  if (order) return finalizeAgainst(intent, order);

  if (intent.phase === CHECKOUT_CLAIMS.finalizing) {
    // The decision is finalization and no order exists yet. Finish it from the
    // snapshot; refunding a checkout that already chose to sell is forbidden.
    return continueFinalization(intent, staleAfterMs);
  }

  return releaseAndClose(intent, 'CHECKOUT_ABANDONED', staleAfterMs);
}

/**
 * One bounded sweep. Never a tight loop, never unbounded work.
 *
 * Finalized intents are swept too, because a lingering marker is exactly the
 * state a crash between finalization and cleanup leaves behind.
 */
export async function reconcileStaleCheckouts({
  now = Date.now(),
  staleAfterMs = CHECKOUT_STALE_LEASE_MS,
  limit = RECONCILE_BATCH_LIMIT
} = {}) {
  const cutoff = new Date(now - staleAfterMs);
  const candidates = await CheckoutIntent.find({
    // Stale claims are swept too: a worker that died holding `finalizing` or
    // `releasing` would otherwise strand its reservation forever.
    phase: { $in: [...RECLAIMABLE_PHASES, 'finalized'] },
    updatedAt: { $lte: cutoff }
  })
    .sort({ updatedAt: 1 })
    .limit(limit);

  const summary = {
    inspected: candidates.length,
    finalized: 0,
    released: 0,
    markerCleaned: 0,
    skipped: 0
  };

  for (const intent of candidates) {
    // A finalized intent with no outstanding marker is already settled; the
    // sweep must not keep re-touching it.
    if (intent.phase === 'finalized') {
      const outstanding = await Business.exists({
        _id: intent.business,
        'stockReservations.intent': intent._id
      });

      if (!outstanding) {
        summary.skipped += 1;
        continue;
      }
    }

    summary[await reconcileIntent(intent, staleAfterMs)] += 1;
  }

  return summary;
}

/**
 * Starts the periodic sweep.
 *
 * The timer is unref'd, so it can never hold the process (or a test runner)
 * open, and a failing sweep is logged by code only - a reconciliation problem
 * must not take the API down or print customer data.
 */
export function startCheckoutReconciler({
  intervalMs = RECONCILE_INTERVAL_MS,
  staleAfterMs = CHECKOUT_STALE_LEASE_MS
} = {}) {
  const sweep = async () => {
    try {
      await reconcileStaleCheckouts({ staleAfterMs });
    } catch (error) {
      console.error('checkout reconciliation failed', safeErrorCode(error));
    }
  };

  // One bounded pass at startup recovers whatever the previous process left
  // behind. It is deliberately not awaited: the API must come up either way.
  void sweep();

  const timer = setInterval(sweep, intervalMs);
  if (typeof timer.unref === 'function') timer.unref();

  return timer;
}
