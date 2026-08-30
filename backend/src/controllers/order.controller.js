import crypto from 'node:crypto';

import mongoose from 'mongoose';

import { Business } from '../models/Business.js';
import { CheckoutIntent } from '../models/CheckoutIntent.js';
import { Order } from '../models/Order.js';
import {
  addressMutableStatuses,
  customerCancellableStatuses,
  orderStatusGroups as policyStatusGroups
} from '../policies/order-status.policy.js';

import {
  CLAIM_ERRORS,
  CONVERGENCE_ATTEMPTS,
  CONVERGENCE_INTERVAL_MS,
  IDEMPOTENCY_ERRORS,
  buildReservationSettlement,
  checkoutFingerprint,
  isAbandoned,
  isTerminal
} from '../policies/checkout-intent.policy.js';
import {
  CHECKOUT_ERRORS,
  DEFAULT_DELIVERY_OPTION,
  DELIVERY_OPTIONS,
  deliveryFeeFor,
  isDeliveryOption,
  normalizeRequestedItems,
  resolveOrderLines,
  subtotalFor,
  totalFor
} from '../policies/checkout.policy.js';
import { paginationParams } from '../policies/query.policy.js';
import {
  claimFinalization,
  confirmFinalization
} from '../services/checkout-claim.service.js';
import {
  RESERVATION_OUTCOMES,
  attemptReservation,
  normalizedFence,
  refreshReservationAuthority,
  reservationOutcome,
  resolveReservationFailure,
  withdrawReservationFailure
} from '../services/checkout-reservation.service.js';
import {
  notifyOrderCancelledByCustomer,
  notifyOrderPlaced
} from '../services/notification.service.js';
import {
  publishOrderTrackingChanged
} from '../realtime/realtime.publisher.js';
import { AppError } from '../utils/AppError.js';
import { asyncHandler } from '../utils/asyncHandler.js';

const validGroups = new Set(policyStatusGroups);
const cancellableStatuses = new Set(customerCancellableStatuses);

/**
 * Rejects a malformed order id before any query runs.
 *
 * `getMyOrder` and `cancelMyOrder` previously passed the raw parameter straight
 * into Mongoose, so a malformed id produced a cast error rather than a clean
 * 400. A well-formed but unknown id still falls through to the existing 404, so
 * ownership is not disclosed.
 */
function requireOrderId(value) {
  if (!mongoose.isValidObjectId(value)) {
    throw new AppError('Order id is invalid', 400, 'INVALID_ORDER_ID');
  }

  return value;
}

function cleanClientOrderId(value) {
  const normalized = String(value ?? '').trim();
  return normalized || null;
}

const checkoutFailures = {
  [CHECKOUT_ERRORS.duplicateQuantity]: {
    status: 400,
    message: 'Product quantity is invalid'
  },
  [CHECKOUT_ERRORS.variantRequired]: {
    status: 400,
    message: 'A product variant must be selected'
  },
  [CHECKOUT_ERRORS.variantNotAvailable]: {
    status: 409,
    message: 'The selected product variant is not available'
  },
  [CHECKOUT_ERRORS.notAvailable]: {
    status: 409,
    message: 'One or more products are not available'
  },
  [CHECKOUT_ERRORS.outOfStock]: {
    status: 409,
    message: 'One or more products are out of stock'
  },
  [CHECKOUT_ERRORS.insufficientStock]: {
    status: 409,
    // Deliberately vague about how many units remain: the exact finite stock
    // quantity is merchant-private and must not leak through an error.
    message: 'One or more products do not have enough stock'
  },
  [IDEMPOTENCY_ERRORS.keyReused]: {
    status: 409,
    message: 'This order id was already used for a different order'
  },
  [IDEMPOTENCY_ERRORS.inProgress]: {
    status: 409,
    message: 'This order is still being processed, please retry'
  },
  [CLAIM_ERRORS.lost]: {
    status: 409,
    message: 'This checkout was settled by another process, please retry'
  }
};

function checkoutFailure(code) {
  const failure = checkoutFailures[code] ?? {
    status: 409,
    message: 'Order could not be accepted'
  };

  return new AppError(failure.message, failure.status, code);
}

function findExistingOrder(userId, clientOrderId) {
  return Order.findOne({ user: userId, clientOrderId });
}

function isDuplicateKeyError(error) {
  return error?.code === 11000;
}

function wait(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

/**
 * Without a client-supplied idempotency key there is nothing to recover a
 * crashed checkout by, so one is generated. It gives every order durable
 * checkout state; it does not invent cross-request idempotency, because a later
 * retry is a genuinely new request and generates a new key.
 */
function checkoutKey(value) {
  return value ?? `srv-${crypto.randomUUID()}`;
}

function orderResponse(res, order, { duplicated }) {
  return res.status(duplicated ? 200 : 201).json({
    success: true,
    data: { order: order.toClientJSON(), duplicated }
  });
}

/**
 * Reserves finite inventory for this intent, exactly once.
 *
 * The update carries the intent id, so replaying it after an interruption
 * matches nothing rather than decrementing again. A non-match therefore has two
 * possible meanings, and they are told apart by looking for the marker: either
 * this intent already holds the reservation (resume), or the stock genuinely is
 * not there (fail).
 */
/**
 * At most one re-evaluation. A merchant may change a product's stock semantics
 * while a checkout is in flight, and the customer should be judged against what
 * is true now - but a loop here would be a spin against a merchant who keeps
 * editing, so the second miss is final.
 */
const RESERVE_ATTEMPTS = 2;

/**
 * Re-prices what a live reservation is actually holding.
 *
 * Used when this worker loses the failure claim to a concurrent worker on the
 * SAME checkout: the basket is identical by fingerprint, so the held quantities
 * are this checkout's quantities, and the order must be built from what was
 * genuinely consumed rather than from what this worker had hoped to consume.
 */
function linesForHeldReservation({ business, held }) {
  const resolved = resolveOrderLines({
    products: business.products,
    items: held.map((line) => ({
      productId: String(line.productId),
      ...(line.variantId
        ? { variantId: String(line.variantId) }
        : {}),
      quantity: line.quantity
    }))
  });

  return resolved.error ? null : resolved.lines;
}

async function reserveStock({
  intent,
  businessId,
  lines,
  normalizedItems
}) {
  let attemptLines = lines;
  let workingIntent = intent;
  let reservationHeld = false;

  for (let attempt = 0; attempt < RESERVE_ATTEMPTS; attempt += 1) {
    const expectedFence = normalizedFence(
      workingIntent.reservationFence
    );

    const reserved = await attemptReservation({
      businessId,
      intentId: workingIntent._id,
      lines: attemptLines,
      reservationFence: expectedFence
    });

    if (reserved.matched) {
      reservationHeld = true;
      break;
    }

    const outcome = await reservationOutcome({
      businessId,
      intentId: workingIntent._id
    });

    if (outcome.state === RESERVATION_OUTCOMES.reserved) {
      const holder = await Business.findOne({
        _id: businessId
      });

      const held = holder
        ? linesForHeldReservation({
            business: holder,
            held: outcome.lines
          })
        : null;

      if (!held) {
        throw checkoutFailure(
          IDEMPOTENCY_ERRORS.inProgress
        );
      }

      attemptLines = held;
      reservationHeld = true;
      break;
    }

    if (outcome.state === RESERVATION_OUTCOMES.failed) {
      throw checkoutFailure(
        outcome.failureCode ??
          CHECKOUT_ERRORS.outOfStock
      );
    }

    /**
     * No outcome exists for this intent.
     *
     * Refresh reservation authority only while the CheckoutIntent is still
     * prepared. A released/finalizing/releasing/finalized checkout can never
     * obtain a new generation.
     */
    const authority = await refreshReservationAuthority({
      intentId: workingIntent._id,
      businessId
    });

    if (!authority.owned) {
      if (
        authority.converge ===
        RESERVATION_OUTCOMES.failed
      ) {
        throw checkoutFailure(
          authority.failureCode ??
            CHECKOUT_ERRORS.outOfStock
        );
      }

      if (
        authority.converge ===
        RESERVATION_OUTCOMES.reserved
      ) {
        const settled = await reservationOutcome({
          businessId,
          intentId: workingIntent._id
        });

        const holder = await Business.findOne({
          _id: businessId
        });

        const held =
          settled.state ===
            RESERVATION_OUTCOMES.reserved &&
          holder
            ? linesForHeldReservation({
                business: holder,
                held: settled.lines
              })
            : null;

        if (!held) {
          throw checkoutFailure(
            IDEMPOTENCY_ERRORS.inProgress
          );
        }

        attemptLines = held;
        reservationHeld = true;
        break;
      }

      const current =
        await CheckoutIntent.findById(
          workingIntent._id
        );

      if (current?.phase === 'released') {
        throw checkoutFailure(
          current.failureCode ??
            CHECKOUT_ERRORS.outOfStock
        );
      }

      throw checkoutFailure(
        IDEMPOTENCY_ERRORS.inProgress
      );
    }

    // From this point onward use the durable refreshed generation, never the
    // stale in-memory intent that entered this function.
    workingIntent = authority.intent;

    const recheck = await Business.findOne({
      _id: businessId,
      isActive: true
    });

    const diagnosis = recheck
      ? resolveOrderLines({
          products: recheck.products,
          items: normalizedItems
        })
      : {
          error: CHECKOUT_ERRORS.notAvailable
        };

    if (!diagnosis.error) {
      if (
        attempt + 1 <
        RESERVE_ATTEMPTS
      ) {
        attemptLines = diagnosis.lines;
        continue;
      }

      // Inventory remains purchasable. Only repeated contention exhausted the
      // bounded retry budget; that is not truthful grounds for a stock error.
      throw checkoutFailure(
        IDEMPOTENCY_ERRORS.inProgress
      );
    }

    const code = diagnosis.error;

    /**
     * Terminal failure is itself a fenced Business write.
     *
     * Success means:
     *   - the temporary failed outcome was recorded; and
     *   - reservationFence was permanently advanced.
     *
     * Therefore every worker carrying this generation or an older one is now
     * unable to decrement inventory.
     */
    const decision =
      await resolveReservationFailure({
        businessId,
        intentId: workingIntent._id,
        failureCode: code,
        reservationFence: normalizedFence(
          workingIntent.reservationFence
        )
      });

    if (
      decision.converge ===
      RESERVATION_OUTCOMES.failed
    ) {
      throw checkoutFailure(
        decision.failureCode ?? code
      );
    }

    if (
      decision.converge ===
      RESERVATION_OUTCOMES.reserved
    ) {
      const holder = await Business.findOne({
        _id: businessId
      });

      const held = holder
        ? linesForHeldReservation({
            business: holder,
            held: decision.lines
          })
        : null;

      if (!held) {
        throw checkoutFailure(
          IDEMPOTENCY_ERRORS.inProgress
        );
      }

      attemptLines = held;
      reservationHeld = true;
      break;
    }

    if (
      decision.converge ===
        RESERVATION_OUTCOMES.staleFence ||
      decision.converge ===
        RESERVATION_OUTCOMES.open ||
      !decision.owned
    ) {
      // An unrelated checkout may have rotated the Business generation.
      // That is contention, not evidence that this customer's stock is gone.
      throw checkoutFailure(
        IDEMPOTENCY_ERRORS.inProgress
      );
    }

    /**
     * The Business-side terminal decision already won.
     *
     * Move the CheckoutIntent to released only if it is still the same prepared
     * checkout carrying the generation under which this worker decided.
     */
    const released =
      await CheckoutIntent.updateOne(
        {
          _id: workingIntent._id,
          phase: 'prepared',
          reservationFence: normalizedFence(
            workingIntent.reservationFence
          )
        },
        {
          $set: {
            phase: 'released',
            failureCode: code
          }
        }
      );

    if (released.matchedCount === 0) {
      /**
       * Do NOT roll reservationFence backwards.
       *
       * The generation rotation is permanent. Only remove this intent's
       * temporary failure bookkeeping.
       */
      await withdrawReservationFailure({
        businessId,
        intentId: workingIntent._id
      });

      const current =
        await CheckoutIntent.findById(
          workingIntent._id
        );

      if (current?.phase === 'released') {
        throw checkoutFailure(
          current.failureCode ?? code
        );
      }

      throw checkoutFailure(
        IDEMPOTENCY_ERRORS.inProgress
      );
    }

    throw checkoutFailure(code);
  }

  if (!reservationHeld) {
    throw checkoutFailure(
      IDEMPOTENCY_ERRORS.inProgress
    );
  }

  /**
   * Persist the post-reservation phase.
   *
   * matchedCount is authoritative. A worker that cannot perform this transition
   * must not continue toward Order creation merely because it once observed a
   * successful Business write.
   */
  const reservedTransition =
    await CheckoutIntent.updateOne(
      {
        _id: workingIntent._id,
        phase: 'prepared',
        reservationFence: normalizedFence(
          workingIntent.reservationFence
        )
      },
      {
        $set: {
          phase: 'reserved',
          lines: attemptLines.map((line) => ({
            productId: line.product._id,
            variantId: line.variantId ?? null,
            quantity: line.quantity,
            finite: line.finite
          }))
        }
      }
    );

  if (reservedTransition.matchedCount === 0) {
    const current =
      await CheckoutIntent.findById(
        workingIntent._id
      );

    if (current?.phase === 'released') {
      throw checkoutFailure(
        current.failureCode ??
          CHECKOUT_ERRORS.outOfStock
      );
    }

    if (
      !current ||
      ![
        'reserved',
        'finalizing',
        'finalized'
      ].includes(current.phase)
    ) {
      /**
       * The Business-side marker remains recoverable. Do not proceed into
       * Order creation when this worker failed to persist its intent transition.
       */
      throw checkoutFailure(
        IDEMPOTENCY_ERRORS.inProgress
      );
    }
  }

  return attemptLines;
}

/**
 * Retires a settled reservation.
 *
 * A pull with NO increment: once an order exists the stock belongs to it, so
 * this is bookkeeping, not a refund. It is the ONLY inventory write the request
 * path performs after a finalization decision: giving stock back once that
 * decision stands is forbidden, and belongs to the release path alone.
 * Idempotent: with the marker already gone the filter simply matches nothing.
 */
async function settleReservation({ intent, businessId }) {
  const settlement = buildReservationSettlement({
    businessId,
    intentId: intent._id
  });

  await Business.updateOne(settlement.filter, settlement.update);
}

/**
 * Writes the order and settles the reservation.
 *
 * A duplicate-key rejection means a concurrent worker on the SAME intent got
 * there first; that is convergence, not failure, so the existing order is
 * adopted rather than a second one created.
 */
/**
 * Writes the order, but only under an acquired finalization claim.
 *
 * Acquiring the claim IS the decision to sell, and it is irrevocable: from here
 * the checkout can only become an order. That is why the draft is frozen into
 * the intent by the very same write - a crash on the next line is then finished
 * by recovery rather than refunded, and the price the customer committed to is
 * the one that survives.
 *
 * Every decisive transition below checks what the database actually did, and is
 * fenced by the claim's token so a worker whose claim was taken over cannot act
 * on ownership it no longer has.
 */
async function finalizeCheckout({ intent, businessId, orderDraft }) {
  const claimed = await claimFinalization({
    intentId: intent._id,
    snapshot: { orderDraft }
  });

  if (!claimed) {
    // Release already owns it, or it is already terminal. Never create an order
    // for a checkout this worker does not own.
    const current = await CheckoutIntent.findById(intent._id);

    if (current?.phase === 'finalized' && current.order) {
      const existing = await Order.findById(current.order);
      if (existing) return existing;
    }

    throw checkoutFailure(
      current?.phase === 'released'
        ? current.failureCode ?? CLAIM_ERRORS.lost
        : CLAIM_ERRORS.lost
    );
  }

  let order = null;

  try {
    order = await Order.create(orderDraft);
  } catch (error) {
    // Any failure, not only a duplicate key: a write can also land and still
    // report an error. Looking for the order first is what stops this worker
    // from concluding "nothing was sold" when something was.
    order = await findExistingOrder(orderDraft.user, orderDraft.clientOrderId);

    if (!order) {
      // The decision to finalize stands, and so does the snapshot that can
      // complete it. Giving the stock back here would be the one reversal this
      // design forbids - a resumed finalization could then sell inventory that
      // had already been refunded - so the worker reports the failure and
      // leaves the order for recovery to write.
      throw error;
    }
  }

  // The intent records the durable order FIRST, so a crash before the marker
  // comes off is recoverable rather than ambiguous. Conditional on the claim
  // still being ours.
  const finalized = await confirmFinalization({
    intentId: intent._id,
    orderId: order._id,
    claimToken: claimed.claimToken
  });

  if (!finalized.owned) {
    // The claim was taken over - only possible if this worker stalled past the
    // abandonment lease. A finalization can only be taken over by ANOTHER
    // FINALIZER, so whoever holds it now is also writing this same order: the
    // unique {user, clientOrderId} key converges them. The order is valid and
    // is never deleted; deleting it was only ever needed to undo a refund that
    // can no longer happen.
    const current = await CheckoutIntent.findById(intent._id);

    if (current?.phase === 'finalized' && current.order) {
      const settledOrder = await Order.findById(current.order);
      if (settledOrder) return settledOrder;
    }

    return order;
  }

  await settleReservation({ intent, businessId });

  return order;
}

/**
 * Waits, boundedly, for another worker on the same intent to reach a terminal
 * phase.
 *
 * Returns the terminal intent, or null if it is still in flight - in which case
 * the caller takes the work over rather than waiting forever, so a worker that
 * died mid-checkout cannot strand the key.
 */
async function awaitConvergence(intentId) {
  for (let attempt = 0; attempt < CONVERGENCE_ATTEMPTS; attempt += 1) {
    await wait(CONVERGENCE_INTERVAL_MS);
    const current = await CheckoutIntent.findById(intentId);

    if (!current) return null;
    if (isTerminal(current.phase)) return current;
  }

  return null;
}

// The delivery tiers a buyer may choose between, priced by the policy that
// charges them.
//
// The checkout screen has to draw both prices, and a price the client carries
// is a price the client can be wrong about — so it reads them from here
// instead. Public: nothing about it is per-user, and a shopper deciding
// whether to check out should not have to authenticate to see the fee.
export const listDeliveryOptions = asyncHandler(async (_req, res) => {
  res.json({
    success: true,
    data: {
      defaultOption: DEFAULT_DELIVERY_OPTION,
      options: Object.entries(DELIVERY_OPTIONS).map(([option, fee]) => ({
        option,
        fee
      }))
    }
  });
});

export const createOrder = asyncHandler(async (req, res) => {
  const clientOrderId = checkoutKey(cleanClientOrderId(req.body.clientOrderId));

  const businessId = String(req.body.businessId ?? '');
  if (!mongoose.isValidObjectId(businessId)) {
    throw new AppError('Business id is invalid', 400, 'INVALID_BUSINESS_ID');
  }

  const business = await Business.findOne({
    _id: businessId,
    isActive: true
  }).select('+reservationFence');

  if (!business) {
    throw new AppError('Business is not available', 404, 'BUSINESS_NOT_FOUND');
  }

  const normalized = normalizeRequestedItems(req.body.items);
  if (normalized.error) {
    throw checkoutFailure(normalized.error);
  }

  const resolved = resolveOrderLines({
    products: business.products,
    items: normalized.items
  });
  if (resolved.error) {
    throw checkoutFailure(resolved.error);
  }

  let { lines } = resolved;
  const deliveryAddress = String(
    req.body.deliveryAddress ?? req.user.address ?? ''
  ).trim();

  // Validated before any durable state exists, so a missing address can never
  // leave an intent or a reservation behind.
  if (deliveryAddress.length < 3) {
    throw new AppError(
      'A delivery address is required',
      400,
      'DELIVERY_ADDRESS_REQUIRED'
    );
  }

  const paymentMethod = req.body.paymentMethod ?? 'cash';

  // The buyer names a tier and nothing more: its price is the policy's, and an
  // unknown name is refused here rather than resolved to the cheapest one.
  const deliveryOption = req.body.deliveryOption ?? DEFAULT_DELIVERY_OPTION;
  if (!isDeliveryOption(deliveryOption)) {
    throw new AppError(
      'Delivery option is invalid',
      400,
      'INVALID_DELIVERY_OPTION'
    );
  }

  const fingerprint = checkoutFingerprint({
    businessId,
    items: normalized.items,
    deliveryAddress,
    paymentMethod,
    deliveryOption
  });
  const intentLines = lines.map((line) => ({
    productId: line.product._id,
    variantId: line.variantId ?? null,
    quantity: line.quantity,
    finite: line.finite
  }));

  // ---- durable identity, BEFORE anything can touch inventory ---------------
  //
  // The unique {user, clientOrderId} index decides the single owner: whoever
  // inserts does the work, everyone else converges on it. There is no state in
  // which stock is consumed and nothing on disk explains why.
  let intent = null;
  let owned = false;

  try {
    intent = await CheckoutIntent.create({
      user: req.user._id,
      clientOrderId,
      fingerprint,
            business: business._id,
            phase: 'prepared',
            reservationFence: normalizedFence(
              business.reservationFence
            ),
            lines: intentLines
    });
    owned = true;
  } catch (error) {
    if (!isDuplicateKeyError(error)) throw error;

    intent = await CheckoutIntent.findOne({
      user: req.user._id,
      clientOrderId
    });
    if (!intent) throw error;
  }

  // Reusing a key for a different basket is a client bug, not a retry.
  if (intent.fingerprint !== fingerprint) {
    throw checkoutFailure(IDEMPOTENCY_ERRORS.keyReused);
  }

  if (intent.phase === 'finalized') {
    const existing = intent.order
      ? await Order.findById(intent.order)
      : await findExistingOrder(req.user._id, clientOrderId);

    if (existing) {
      // CRASH-FINAL-01: the order and the intent are durable, but the process
      // may have died before the marker came off. Clearing it here is a pull
      // with no increment, so it can never give back stock the order owns, and
      // it is idempotent when the marker is already gone.
      await settleReservation({ intent, businessId: business._id });

      return orderResponse(res, existing, { duplicated: true });
    }
  }

  // A checkout that already failed terminally answers the same way every time,
  // and never reserves a second time.
  if (intent.phase === 'released') {
    throw checkoutFailure(intent.failureCode ?? CHECKOUT_ERRORS.outOfStock);
  }

  if (!owned && isAbandoned(intent, Date.now())) {
    // Nobody has touched this intent for longer than the whole convergence
    // window, so there is no live worker to wait for. Take it over at once
    // rather than making every crash recovery sit out the full timeout.
    owned = true;
  }

  if (!owned) {
    // Another request owns this exact checkout. Wait for it rather than racing
    // it into a stock error that would misdescribe an identical retry.
    const converged = await awaitConvergence(intent._id);

    if (converged?.phase === 'finalized' && converged.order) {
      const existing = await Order.findById(converged.order);
      if (existing) return orderResponse(res, existing, { duplicated: true });
    }
    if (converged?.phase === 'released') {
      throw checkoutFailure(converged.failureCode ?? CHECKOUT_ERRORS.outOfStock);
    }

    // Still unfinished: the owner may have died, so take the work over. Every
    // phase transition below is conditional and idempotent, which is what makes
    // that safe.
    const current = await CheckoutIntent.findById(intent._id);
    if (!current) throw checkoutFailure(IDEMPOTENCY_ERRORS.inProgress);
    intent = current;
  }

  if (intent.phase === 'prepared') {
    // The reservation may have been re-evaluated against fresher product
    // truth, so downstream pricing and release use what was actually taken.
    lines = await reserveStock({
      intent,
      businessId: business._id,
      lines,
      normalizedItems: normalized.items
    });
  }

  const subtotal = subtotalFor(lines);
  const order = await finalizeCheckout({
    intent,
    businessId: business._id,
    orderDraft: {
      clientOrderId,
      user: req.user._id,
      customerName: req.user.name,
      customerPhone: req.user.phone ?? req.user.phones?.[0]?.value ?? '',
      business: business._id,
      businessName: business.name,
      businessAddress: business.address,
      items: lines.map((line) => ({
        productId: line.product._id,
        name: line.product.name,
        imageUrl:
          [...(line.product.imageUrls ?? []), line.product.imageUrl].find(
            Boolean
          ) ?? '',
        // The server-derived sale price, snapshotted at purchase time. A later
        // merchant price or discount change cannot rewrite this order.
        unitPrice: line.unitPrice,
        quantity: line.quantity,
        // Both values come from the selected server-owned variant. `variantId`
        // preserves identity; `variant` preserves the purchase-time label.
        variantId: line.variantId ?? null,
        variant: line.variantLabel ?? ''
      })),
      subtotal,
      // The buyer names a tier; its price comes from the policy, never from
      // the request body.
      deliveryOption,
      deliveryFee: deliveryFeeFor(subtotal, deliveryOption),
      total: totalFor(subtotal, deliveryOption),
      deliveryAddress,
      paymentMethod
    }
  });

  // Everything below is best-effort and runs AFTER the order is durable. A
  // failure here must never release inventory or invalidate the order.
  if (business.owner) {
    await notifyOrderPlaced({
      ownerId: business.owner,
      businessId: business._id,
      order
    });
  }

  return orderResponse(res, order, { duplicated: false });
});

export const listMyOrders = asyncHandler(async (req, res) => {
  const { page, limit, skip } = paginationParams(req.query);
  const requestedGroup = String(req.query.status ?? '').trim();
  const filter = { user: req.user._id };

  if (requestedGroup) {
    if (!validGroups.has(requestedGroup)) {
      throw new AppError('Order status filter is invalid', 400, 'INVALID_ORDER_STATUS');
    }
    filter.statusGroup = requestedGroup;
  }

  const [orders, total, groupedCounts] = await Promise.all([
    Order.find(filter).sort({ createdAt: -1, _id: -1 }).skip(skip).limit(limit),
    Order.countDocuments(filter),
    Order.aggregate([
      { $match: { user: req.user._id } },
      { $group: { _id: '$statusGroup', count: { $sum: 1 } } }
    ])
  ]);

  const counts = { current: 0, completed: 0, cancelled: 0, total: 0 };
  for (const entry of groupedCounts) {
    if (validGroups.has(entry._id)) {
      counts[entry._id] = entry.count;
      counts.total += entry.count;
    }
  }

  res.json({
    success: true,
    data: {
      orders: orders.map((order) => order.toClientJSON()),
      counts,
      pagination: {
        page,
        limit,
        total,
        hasMore: skip + orders.length < total
      }
    }
  });
});

export const getMyOrder = asyncHandler(async (req, res) => {
  const orderId = requireOrderId(req.params.id);
  const order = await Order.findOne({ _id: orderId, user: req.user._id });

  if (!order) {
    throw new AppError('Order was not found', 404, 'ORDER_NOT_FOUND');
  }

  res.json({ success: true, data: { order: order.toClientJSON() } });
});

/**
 * The tracking screen lets a customer correct the delivery address, but only
 * while the merchant has not started preparing the order.
 */
export const updateMyOrderAddress = asyncHandler(async (req, res) => {
  const orderId = requireOrderId(req.params.id);
  const deliveryAddress = String(req.body.deliveryAddress).trim();
  const order = await Order.findOneAndUpdate(
    {
      _id: orderId,
      user: req.user._id,
      status: { $in: addressMutableStatuses }
    },
    { $set: { deliveryAddress } },
    { new: true, runValidators: true }
  );

  if (!order) {
    const exists = await Order.exists({ _id: orderId, user: req.user._id });
    if (!exists) {
      throw new AppError('Order was not found', 404, 'ORDER_NOT_FOUND');
    }
    throw new AppError(
      'The delivery address can no longer be changed',
      409,
      'ORDER_ADDRESS_LOCKED'
    );
  }

  res.json({ success: true, data: { order: order.toClientJSON() } });
});

export const cancelMyOrder = asyncHandler(async (req, res) => {
  const orderId = requireOrderId(req.params.id);
  const reason = String(req.body.reason ?? '').trim();
  const cancelledAt = new Date();
  const order = await Order.findOneAndUpdate(
    {
      _id: orderId,
      user: req.user._id,
      status: { $in: [...cancellableStatuses] }
    },
    {
      $set: {
        status: 'cancelled',
        statusGroup: 'cancelled',
        cancellationReason: reason,
        cancelledAt,
        'courierLocationCapability.tokenHash': '',
        'courierLocationCapability.revokedAt':
          cancelledAt,
        courierLocation: null
      },
      $push: {
        statusHistory: { status: 'cancelled', changedAt: cancelledAt, note: reason }
      }
    },
    { new: true, runValidators: true }
  );

  if (!order) {
    const exists = await Order.exists({ _id: orderId, user: req.user._id });
    if (!exists) {
      throw new AppError('Order was not found', 404, 'ORDER_NOT_FOUND');
    }
    throw new AppError(
      'This order can no longer be cancelled',
      409,
      'ORDER_NOT_CANCELLABLE'
    );
  }

  publishOrderTrackingChanged({
    recipientIds: [order.user],
    orderId: order._id,
    reason: 'order-status-changed'
  });

  const business = await Business.findById(order.business).select('owner');
  if (business?.owner) {
    await notifyOrderCancelledByCustomer({
      ownerId: business.owner,
      businessId: order.business,
      order
    });
  }

  res.json({ success: true, data: { order: order.toClientJSON() } });
});
