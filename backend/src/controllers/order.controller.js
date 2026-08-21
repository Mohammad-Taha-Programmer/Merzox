import mongoose from 'mongoose';

import { Business } from '../models/Business.js';
import { Order } from '../models/Order.js';
import {
  notifyOrderCancelledByCustomer,
  notifyOrderPlaced
} from '../services/notification.service.js';
import { AppError } from '../utils/AppError.js';
import { asyncHandler } from '../utils/asyncHandler.js';

const validGroups = new Set(['current', 'completed', 'cancelled']);
const cancellableStatuses = new Set(['pending', 'confirmed', 'preparing']);

function paginationParams(query) {
  const page = Math.max(Number.parseInt(query.page ?? '1', 10), 1);
  const limit = Math.min(
    Math.max(Number.parseInt(query.limit ?? '20', 10), 1),
    50
  );

  return { page, limit, skip: (page - 1) * limit };
}

function cleanClientOrderId(value) {
  const normalized = String(value ?? '').trim();
  return normalized || null;
}

export const createOrder = asyncHandler(async (req, res) => {
  const clientOrderId = cleanClientOrderId(req.body.clientOrderId);

  if (clientOrderId) {
    const existing = await Order.findOne({
      user: req.user._id,
      clientOrderId
    });

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

  const requestedItems = req.body.items;
  const activeProducts = new Map(
    business.products
      .filter((product) => product.isActive)
      .map((product) => [product._id.toString(), product])
  );

  const items = requestedItems.map((requested) => {
    const productId = String(requested.productId ?? '');
    const product = activeProducts.get(productId);

    if (!product) {
      throw new AppError(
        'One or more products are not available',
        409,
        'PRODUCT_NOT_AVAILABLE'
      );
    }

    const quantity = Number(requested.quantity);
    const imageUrl =
      [...(product.imageUrls ?? []), product.imageUrl].find(Boolean) ?? '';

    return {
      productId: product._id,
      name: product.name,
      imageUrl,
      unitPrice: Number(product.price ?? 0),
      quantity,
      variant: String(requested.variant ?? '').trim()
    };
  });

  const subtotal = items.reduce(
    (sum, item) => sum + item.unitPrice * item.quantity,
    0
  );
  const deliveryFee = subtotal > 0 ? 10 : 0;
  const deliveryAddress = String(
    req.body.deliveryAddress ?? req.user.address ?? ''
  ).trim();

  if (deliveryAddress.length < 3) {
    throw new AppError(
      'A delivery address is required',
      400,
      'DELIVERY_ADDRESS_REQUIRED'
    );
  }

  const order = await Order.create({
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
    total: subtotal + deliveryFee,
    deliveryAddress,
    paymentMethod: req.body.paymentMethod ?? 'cash'
  });

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
  const order = await Order.findOne({ _id: req.params.id, user: req.user._id });

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
  if (!mongoose.isValidObjectId(req.params.id)) {
    throw new AppError('Order id is invalid', 400, 'INVALID_ORDER_ID');
  }

  const deliveryAddress = String(req.body.deliveryAddress).trim();
  const order = await Order.findOneAndUpdate(
    {
      _id: req.params.id,
      user: req.user._id,
      status: { $in: ['pending', 'confirmed'] }
    },
    { $set: { deliveryAddress } },
    { new: true, runValidators: true }
  );

  if (!order) {
    const exists = await Order.exists({ _id: req.params.id, user: req.user._id });
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
  const reason = String(req.body.reason ?? '').trim();
  const cancelledAt = new Date();
  const order = await Order.findOneAndUpdate(
    {
      _id: req.params.id,
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
    const exists = await Order.exists({ _id: req.params.id, user: req.user._id });
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
