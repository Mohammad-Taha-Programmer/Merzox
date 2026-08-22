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
  CLAIMABLE_PHASES,
  CLAIM_ERRORS,
  CONVERGENCE_ATTEMPTS,
  CONVERGENCE_INTERVAL_MS,
  IDEMPOTENCY_ERRORS,
  buildIdentifiedRelease,
  buildIdentifiedReservation,
  buildReservationSettlement,
  checkoutFingerprint,
  isAbandoned,
  isTerminal
} from '../policies/checkout-intent.policy.js';
import {
  CHECKOUT_ERRORS,
  deliveryFeeFor,
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
  notifyOrderCancelledByCustomer,
  notifyOrderPlaced
} from '../services/notification.service.js';
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

async function reserveStock({ intent, businessId, lines, normalizedItems }) {
  let attemptLines = lines;

  for (let attempt = 0; attempt < RESERVE_ATTEMPTS; attempt += 1) {
    const reservation = buildIdentifiedReservation({
      businessId,
      intentId: intent._id,
      lines: attemptLines
    });

    const result = await Business.updateOne(
      reservation.filter,
      reservation.update,
      reservation.arrayFilters.length > 0
        ? { arrayFilters: reservation.arrayFilters }
        : undefined
    );

    if (result.matchedCount > 0) break;

    const alreadyHeld = await Business.exists({
      _id: businessId,
      'stockReservations.intent': intent._id
    });
    if (alreadyHeld) break;

    // Nothing matched and nothing is held, so the product moved underneath us.
    // Re-read the truth before deciding whether that is a refusal or simply a
    // different - still purchasable - shape.
    const recheck = await Business.findOne({ _id: businessId, isActive: true });
    const diagnosis = recheck
      ? resolveOrderLines({ products: recheck.products, items: normalizedItems })
      : { error: CHECKOUT_ERRORS.notAvailable };

    const stillPurchasable =
      !diagnosis.error && attempt + 1 < RESERVE_ATTEMPTS;

    if (stillPurchasable) {
      // For example: the merchant switched the product to unlimited stock. The
      // basket is genuinely fine now, so reserve against the new semantics
      // rather than failing a customer for a change they never made.
      attemptLines = diagnosis.lines;
      continue;
    }

    const code = diagnosis.error ?? CHECKOUT_ERRORS.outOfStock;

    // Terminal, and there is nothing to give back: no marker means no
    // decrement ever happened for this intent. Conditional on the phase, so a
    // checkout another worker already owns is never overwritten.
    await CheckoutIntent.updateOne(
      { _id: intent._id, phase: { $in: CLAIMABLE_PHASES } },
      { $set: { phase: 'released', failureCode: code } }
    );

    throw checkoutFailure(code);
  }

  // Only after the stock is provably held. A crash before this line leaves the
  // intent in `prepared` with the marker set, and the branch above resumes it
  // without decrementing a second time. The stored lines are whatever was
  // ACTUALLY reserved, so a later release can only give back exactly that.
  await CheckoutIntent.updateOne(
    { _id: intent._id, phase: 'prepared' },
    {
      $set: {
        phase: 'reserved',
        lines: attemptLines.map((line) => ({
          productId: line.product._id,
          quantity: line.quantity,
          finite: line.finite
        }))
      }
    }
  );

  return attemptLines;
}

/**
 * Retires a settled reservation.
 *
 * A pull with NO increment: once an order exists the stock belongs to it, so
 * this is bookkeeping, not a refund. Distinct from `releaseStock` on purpose -
 * the two must never be confused. Idempotent: with the marker already gone the
 * filter simply matches nothing.
 */
async function settleReservation({ intent, businessId }) {
  const settlement = buildReservationSettlement({
    businessId,
    intentId: intent._id
  });

  await Business.updateOne(settlement.filter, settlement.update);
}

/**
 * Gives a reservation back, exactly once.
 *
 * The filter requires the marker to still be present, so a second release
 * changes nothing. There is deliberately no unconditional increment anywhere.
 */
async function releaseStock({ intent, businessId, lines }) {
  const release = buildIdentifiedRelease({
    businessId,
    intentId: intent._id,
    lines
  });

  await Business.updateOne(
    release.filter,
    release.update,
    release.arrayFilters.length > 0
      ? { arrayFilters: release.arrayFilters }
      : undefined
  );
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
 * Every decisive transition below checks what the database actually did. A
 * transition that matched nothing means somebody else owns this checkout, and
 * the only safe response is to undo what this worker created and stop.
 */
async function finalizeCheckout({ intent, businessId, lines, orderDraft }) {
  const claimed = await claimFinalization({ intentId: intent._id });

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
  let createdHere = false;

  try {
    order = await Order.create(orderDraft);
    createdHere = true;
  } catch (error) {
    if (isDuplicateKeyError(error)) {
      order = await findExistingOrder(orderDraft.user, orderDraft.clientOrderId);
    }

    if (!order) {
      // The order could not be persisted at all, so the inventory this intent
      // is holding has to go back - once. This worker still owns the claim, so
      // it is the one entitled to do that.
      await releaseStock({ intent, businessId, lines });
      await CheckoutIntent.updateOne(
        { _id: intent._id, phase: 'finalizing' },
        { $set: { phase: 'released', failureCode: 'CHECKOUT_FAILED' } }
      );

      throw error;
    }
  }

  // The intent records the durable order FIRST, so a crash before the marker
  // comes off is recoverable rather than ambiguous. Conditional on the claim
  // still being ours.
  const finalized = await confirmFinalization({
    intentId: intent._id,
    orderId: order._id
  });

  if (!finalized.owned) {
    // The claim was taken away - only possible if this worker stalled past the
    // abandonment lease and a reconciler took over.
    const current = await CheckoutIntent.findById(intent._id);

    if (current?.phase === 'finalized' && current.order) {
      const settledOrder = await Order.findById(current.order);
      if (settledOrder) return settledOrder;
    }

    // The reservation was given back by whoever took the claim, so the order
    // this worker just wrote must not survive to reference refunded stock.
    if (createdHere) await Order.deleteOne({ _id: order._id });

    throw checkoutFailure(CLAIM_ERRORS.lost);
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

export const createOrder = asyncHandler(async (req, res) => {
  const clientOrderId = checkoutKey(cleanClientOrderId(req.body.clientOrderId));

  const businessId = String(req.body.businessId ?? '');
  if (!mongoose.isValidObjectId(businessId)) {
    throw new AppError('Business id is invalid', 400, 'INVALID_BUSINESS_ID');
  }

  const business = await Business.findOne({ _id: businessId, isActive: true });
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
  const fingerprint = checkoutFingerprint({
    businessId,
    items: normalized.items,
    deliveryAddress,
    paymentMethod
  });
  const intentLines = lines.map((line) => ({
    productId: line.product._id,
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
    lines,
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
        // Left empty on purpose: the catalog has no variant to copy from, and
        // the client is not allowed to define one.
        variant: ''
      })),
      subtotal,
      deliveryFee: deliveryFeeFor(subtotal),
      total: totalFor(subtotal),
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
        cancelledAt
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
