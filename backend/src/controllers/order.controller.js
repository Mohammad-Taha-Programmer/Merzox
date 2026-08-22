import mongoose from 'mongoose';

import { Business } from '../models/Business.js';
import { Order } from '../models/Order.js';
import {
  addressMutableStatuses,
  customerCancellableStatuses,
  orderStatusGroups as policyStatusGroups
} from '../policies/order-status.policy.js';
import {
  CHECKOUT_ERRORS,
  buildStockRelease,
  buildStockReservation,
  deliveryFeeFor,
  normalizeRequestedItems,
  resolveOrderLines,
  subtotalFor,
  totalFor
} from '../policies/checkout.policy.js';
import { paginationParams } from '../policies/query.policy.js';
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

export const createOrder = asyncHandler(async (req, res) => {
  const clientOrderId = cleanClientOrderId(req.body.clientOrderId);

  // First idempotency gate. A retry that arrives after the original completed
  // returns the existing order and reserves nothing.
  if (clientOrderId) {
    const existing = await findExistingOrder(req.user._id, clientOrderId);

    if (existing) {
      return res.status(200).json({
        success: true,
        data: { order: existing.toClientJSON(), duplicated: true }
      });
    }
  }

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

  const { lines } = resolved;
  const deliveryAddress = String(
    req.body.deliveryAddress ?? req.user.address ?? ''
  ).trim();

  // Validated before anything is reserved, so a missing address can never leave
  // inventory held.
  if (deliveryAddress.length < 3) {
    throw new AppError(
      'A delivery address is required',
      400,
      'DELIVERY_ADDRESS_REQUIRED'
    );
  }

  const reservation = buildStockReservation({
    businessId: business._id,
    lines
  });
  // A single conditional document update: either every line was still
  // available and all finite lines were decremented together, or nothing
  // matched and nothing changed. There is no partially consumed basket.
  //
  // An all-unlimited basket consumes nothing, so it only re-asserts the same
  // filter rather than writing to the business document for no reason.
  const matchedCount = reservation.update
    ? (
        await Business.updateOne(reservation.filter, reservation.update, {
          arrayFilters: reservation.arrayFilters
        })
      ).matchedCount
    : await Business.countDocuments(reservation.filter);

  if (matchedCount === 0) {
    const recheck = await Business.findOne({ _id: businessId, isActive: true });

    if (!recheck) {
      throw new AppError('Business is not available', 404, 'BUSINESS_NOT_FOUND');
    }

    const diagnosis = resolveOrderLines({
      products: recheck.products,
      items: normalized.items
    });

    throw checkoutFailure(diagnosis.error ?? CHECKOUT_ERRORS.outOfStock);
  }

  const items = lines.map((line) => {
    const imageUrl =
      [...(line.product.imageUrls ?? []), line.product.imageUrl].find(
        Boolean
      ) ?? '';

    return {
      productId: line.product._id,
      name: line.product.name,
      imageUrl,
      // The server-derived sale price, snapshotted at purchase time. A later
      // merchant price or discount change cannot rewrite this order.
      unitPrice: line.unitPrice,
      quantity: line.quantity,
      // Left empty on purpose: the catalog has no variant to copy from, and the
      // client is not allowed to define one.
      variant: ''
    };
  });

  const subtotal = subtotalFor(lines);
  const deliveryFee = deliveryFeeFor(subtotal);

  let order;
  try {
    order = await Order.create({
      clientOrderId,
      user: req.user._id,
      customerName: req.user.name,
      customerPhone: req.user.phone ?? req.user.phones?.[0]?.value ?? '',
      business: business._id,
      businessName: business.name,
      businessAddress: business.address,
      items,
      subtotal,
      deliveryFee,
      total: totalFor(subtotal),
      deliveryAddress,
      paymentMethod: req.body.paymentMethod ?? 'cash'
    });
  } catch (error) {
    // The reservation already happened, so it has to be given back whatever
    // went wrong - including the idempotency race below, where a concurrent
    // retry won the unique {user, clientOrderId} index.
    const release = buildStockRelease({ businessId: business._id, lines });
    if (release.update) {
      await Business.updateOne(release.filter, release.update, {
        arrayFilters: release.arrayFilters
      });
    }

    if (isDuplicateKeyError(error) && clientOrderId) {
      const existing = await findExistingOrder(req.user._id, clientOrderId);

      if (existing) {
        return res.status(200).json({
          success: true,
          data: { order: existing.toClientJSON(), duplicated: true }
        });
      }
    }

    throw error;
  }

  if (business.owner) {
    await notifyOrderPlaced({
      ownerId: business.owner,
      businessId: business._id,
      order
    });
  }

  res.status(201).json({
    success: true,
    data: { order: order.toClientJSON(), duplicated: false }
  });
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
