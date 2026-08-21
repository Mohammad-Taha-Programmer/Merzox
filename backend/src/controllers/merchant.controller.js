import crypto from 'node:crypto';

import mongoose from 'mongoose';

import { Business } from '../models/Business.js';
import { Order } from '../models/Order.js';
import { User } from '../models/User.js';
import { notifyOrderStatus } from '../services/notification.service.js';
import { AppError } from '../utils/AppError.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { normalizeIdentifier, normalizePhone } from '../utils/normalize.js';

const orderStatuses = new Set([
  'pending',
  'confirmed',
  'preparing',
  'outForDelivery',
  'delivered',
  'cancelled'
]);
const orderStatusGroups = new Set(['current', 'completed', 'cancelled']);
const ownerOrderTransitions = new Map([
  ['pending', new Set(['confirmed', 'cancelled'])],
  ['confirmed', new Set(['preparing', 'cancelled'])],
  ['preparing', new Set(['outForDelivery', 'cancelled'])],
  ['outForDelivery', new Set(['delivered'])],
  ['delivered', new Set()],
  ['cancelled', new Set()]
]);
const productFields = [
  'name',
  'description',
  'price',
  'imageUrl',
  'imageUrls',
  'classification',
  'isService',
  'isActive'
];

function paginationParams(query) {
  const parsedPage = Number.parseInt(query.page ?? '1', 10);
  const parsedLimit = Number.parseInt(query.limit ?? '20', 10);
  const page = Number.isFinite(parsedPage) ? Math.max(parsedPage, 1) : 1;
  const limit = Number.isFinite(parsedLimit)
    ? Math.min(Math.max(parsedLimit, 1), 50)
    : 20;

  return { page, limit, skip: (page - 1) * limit };
}

function createBusinessPublicId() {
  const timePart = Date.now().toString(36).toUpperCase();
  const randomPart = crypto.randomBytes(5).toString('hex').toUpperCase();
  return `MXB-${timePart}-${randomPart}`;
}

async function findOwnedBusiness(req) {
  const business = await Business.findOne({ owner: req.user._id });

  if (!business) {
    throw new AppError('Business profile was not found', 404, 'BUSINESS_PROFILE_NOT_FOUND');
  }

  if (!business.isActive) {
    throw new AppError('Business account is disabled', 403, 'BUSINESS_ACCOUNT_DISABLED');
  }

  return business;
}

function assignProductFields(product, body) {
  for (const field of productFields) {
    if (body[field] !== undefined) {
      product[field] = body[field];
    }
  }
}

function statusGroupFor(status) {
  if (status === 'delivered') return 'completed';
  if (status === 'cancelled') return 'cancelled';
  return 'current';
}

export function canTransitionOwnerOrder(from, to) {
  return ownerOrderTransitions.get(from)?.has(to) ?? false;
}

export const enrollBusiness = asyncHandler(async (req, res) => {
  if (req.user.userType !== 'normal') {
    throw new AppError('This account is already a business account', 409, 'BUSINESS_ALREADY_ENROLLED');
  }

  const user = await User.findById(req.user._id).select('+passwordHash');
  if (!user || !(await user.verifyPassword(String(req.body.currentPassword)))) {
    throw new AppError('Current password is incorrect', 401, 'INVALID_CURRENT_PASSWORD');
  }

  const phone = normalizePhone(req.body.phone);
  const email = normalizeIdentifier(req.body.email);

  if (user.phone && user.phone !== phone) {
    throw new AppError(
      'Phone number must match the current account',
      409,
      'ACCOUNT_PHONE_MISMATCH'
    );
  }
  if (user.email && user.email !== email) {
    throw new AppError(
      'Email must match the current account',
      409,
      'ACCOUNT_EMAIL_MISMATCH'
    );
  }

  const conflictingUser = await User.findOne({
    _id: { $ne: user._id },
    $or: [
      { phone },
      { 'phones.value': phone },
      { email },
      { 'emails.value': email }
    ]
  });
  if (conflictingUser) {
    throw new AppError(
      'Email or phone already belongs to another account',
      409,
      'BUSINESS_IDENTIFIER_EXISTS'
    );
  }

  if (await Business.exists({ owner: user._id })) {
    throw new AppError('This account already owns a business', 409, 'BUSINESS_ALREADY_EXISTS');
  }

  if (!user.phone) {
    user.phone = phone;
    user.phones = [{ value: phone, label: 'mobile', isPrimary: true }];
  }
  if (!user.email) {
    user.email = email;
    user.emailVerified = false;
    user.emails = [
      { value: email, label: 'work', isPrimary: true, verified: false }
    ];
  }

  const business = new Business({
    owner: user._id,
    publicId: createBusinessPublicId(),
    name: String(req.body.name).trim(),
    englishName: String(req.body.englishName ?? '').trim(),
    description: String(req.body.description ?? '').trim(),
    category: String(req.body.category).trim(),
    address: String(req.body.address ?? user.address ?? '').trim(),
    attachmentUrl: String(req.body.attachmentUrl ?? '').trim(),
    contacts: [
      {
        name: user.name,
        phone,
        email
      }
    ]
  });

  await business.save();

  try {
    user.userType = 'business';
    await user.save();
  } catch (error) {
    await Business.deleteOne({ _id: business._id });
    throw error;
  }

  res.status(201).json({
    success: true,
    data: {
      user: user.toSafeJSON(),
      business: business.toOwnerJSON()
    }
  });
});

export const getMyBusiness = asyncHandler(async (req, res) => {
  const business = await findOwnedBusiness(req);
  res.json({ success: true, data: { business: business.toOwnerJSON() } });
});

export const updateMyBusiness = asyncHandler(async (req, res) => {
  const business = await findOwnedBusiness(req);
  const fields = [
    'name',
    'englishName',
    'description',
    'category',
    'address',
    'attachmentUrl',
    'logoUrl'
  ];

  for (const field of fields) {
    if (req.body[field] !== undefined) {
      business[field] = String(req.body[field]).trim();
    }
  }

  if (req.body.socialLinks !== undefined) {
    for (const key of ['instagram', 'whatsapp', 'mobile', 'facebook']) {
      if (req.body.socialLinks[key] !== undefined) {
        business.socialLinks[key] = String(req.body.socialLinks[key]).trim();
      }
    }
  }

  await business.save();
  res.json({ success: true, data: { business: business.toOwnerJSON() } });
});

export const getMyBusinessDashboard = asyncHandler(async (req, res) => {
  const business = await findOwnedBusiness(req);
  const [summary, recentOrders] = await Promise.all([
    Order.aggregate([
      { $match: { business: business._id } },
      {
        $group: {
          _id: null,
          sales: {
            $sum: {
              $cond: [{ $eq: ['$status', 'delivered'] }, '$total', 0]
            }
          },
          orderCount: { $sum: 1 },
          activeOrderCount: {
            $sum: {
              $cond: [{ $eq: ['$statusGroup', 'current'] }, 1, 0]
            }
          }
        }
      }
    ]),
    Order.find({ business: business._id }).sort({ createdAt: -1, _id: -1 }).limit(5)
  ]);
  const totals = summary[0] ?? { sales: 0, orderCount: 0, activeOrderCount: 0 };

  res.json({
    success: true,
    data: {
      dashboard: {
        sales: totals.sales,
        orderCount: totals.orderCount,
        activeOrderCount: totals.activeOrderCount,
        viewCount: business.viewCount,
        recentOrders: recentOrders.map((order) => order.toMerchantJSON())
      }
    }
  });
});

export const listMyBusinessProducts = asyncHandler(async (req, res) => {
  const business = await findOwnedBusiness(req);
  const products = [...business.products]
    .filter((product) => product.isActive)
    .sort((left, right) => right.createdAt - left.createdAt)
    .map((product) => business.productToJSON(product));

  res.json({ success: true, data: { products } });
});

export const createMyBusinessProduct = asyncHandler(async (req, res) => {
  const business = await findOwnedBusiness(req);
  business.products.push({
    name: req.body.name,
    description: req.body.description ?? '',
    price: req.body.price,
    imageUrl: req.body.imageUrl ?? '',
    imageUrls: req.body.imageUrls ?? [],
    classification: req.body.classification ?? 'new',
    isService: req.body.isService ?? false,
    isActive: req.body.isActive ?? true
  });
  const product = business.products[business.products.length - 1];
  await business.save();

  res.status(201).json({
    success: true,
    data: { product: business.productToJSON(product) }
  });
});

export const updateMyBusinessProduct = asyncHandler(async (req, res) => {
  const business = await findOwnedBusiness(req);
  const product = business.products.id(req.params.productId);
  if (!product) {
    throw new AppError('Product not found', 404, 'PRODUCT_NOT_FOUND');
  }

  assignProductFields(product, req.body);
  await business.save();

  res.json({ success: true, data: { product: business.productToJSON(product) } });
});

export const deleteMyBusinessProduct = asyncHandler(async (req, res) => {
  const business = await findOwnedBusiness(req);
  const product = business.products.id(req.params.productId);
  if (!product) {
    throw new AppError('Product not found', 404, 'PRODUCT_NOT_FOUND');
  }

  product.isActive = false;
  await business.save();

  res.json({ success: true, data: { product: business.productToJSON(product) } });
});

export const listMyBusinessOrders = asyncHandler(async (req, res) => {
  const business = await findOwnedBusiness(req);
  const { page, limit, skip } = paginationParams(req.query);
  const requestedStatus = String(req.query.statusGroup ?? req.query.status ?? '').trim();
  const filter = { business: business._id };

  if (requestedStatus) {
    if (orderStatusGroups.has(requestedStatus)) {
      filter.statusGroup = requestedStatus;
    } else if (orderStatuses.has(requestedStatus)) {
      filter.status = requestedStatus;
    } else {
      throw new AppError('Order status filter is invalid', 400, 'INVALID_ORDER_STATUS');
    }
  }

  const [orders, total, groupedCounts] = await Promise.all([
    Order.find(filter).sort({ createdAt: -1, _id: -1 }).skip(skip).limit(limit),
    Order.countDocuments(filter),
    Order.aggregate([
      { $match: { business: business._id } },
      { $group: { _id: '$statusGroup', count: { $sum: 1 } } }
    ])
  ]);
  const counts = { current: 0, completed: 0, cancelled: 0, total: 0 };
  for (const entry of groupedCounts) {
    if (orderStatusGroups.has(entry._id)) {
      counts[entry._id] = entry.count;
      counts.total += entry.count;
    }
  }

  res.json({
    success: true,
    data: {
      orders: orders.map((order) => order.toMerchantJSON()),
      counts,
      pagination: { page, limit, total, hasMore: skip + orders.length < total }
    }
  });
});

export const updateMyBusinessOrderStatus = asyncHandler(async (req, res) => {
  const business = await findOwnedBusiness(req);
  if (!mongoose.isValidObjectId(req.params.orderId)) {
    throw new AppError('Order id is invalid', 400, 'INVALID_ORDER_ID');
  }

  const order = await Order.findOne({
    _id: req.params.orderId,
    business: business._id
  });
  if (!order) {
    throw new AppError('Order was not found', 404, 'ORDER_NOT_FOUND');
  }

  const nextStatus = String(req.body.status);
  if (!canTransitionOwnerOrder(order.status, nextStatus)) {
    throw new AppError(
      `Order cannot move from ${order.status} to ${nextStatus}`,
      409,
      'INVALID_ORDER_STATUS_TRANSITION'
    );
  }

  const changedAt = new Date();
  const note = String(req.body.note ?? '').trim();
  const set = {
    status: nextStatus,
    statusGroup: statusGroupFor(nextStatus)
  };
  if (nextStatus === 'delivered') set.deliveredAt = changedAt;
  if (nextStatus === 'cancelled') {
    set.cancelledAt = changedAt;
    set.cancellationReason = note;
  }

  const updated = await Order.findOneAndUpdate(
    { _id: order._id, business: business._id, status: order.status },
    {
      $set: set,
      $push: { statusHistory: { status: nextStatus, changedAt, note } }
    },
    { new: true, runValidators: true }
  );
  if (!updated) {
    throw new AppError(
      'Order status changed while this request was being processed',
      409,
      'ORDER_STATUS_CONFLICT'
    );
  }

  await notifyOrderStatus({
    userId: updated.user,
    order: updated,
    status: nextStatus
  });

  res.json({ success: true, data: { order: updated.toMerchantJSON() } });
});

/**
 * Assigning a courier is what fills the driver card on the customer's tracking
 * screen, so it is allowed from the moment the order is being prepared.
 */
export const updateMyBusinessOrderCourier = asyncHandler(async (req, res) => {
  const business = await findOwnedBusiness(req);
  if (!mongoose.isValidObjectId(req.params.orderId)) {
    throw new AppError('Order id is invalid', 400, 'INVALID_ORDER_ID');
  }

  const order = await Order.findOneAndUpdate(
    {
      _id: req.params.orderId,
      business: business._id,
      status: { $in: ['confirmed', 'preparing', 'outForDelivery'] }
    },
    {
      $set: {
        courier: {
          name: String(req.body.name).trim(),
          phone: String(req.body.phone ?? '').trim(),
          assignedAt: new Date()
        }
      }
    },
    { new: true, runValidators: true }
  );

  if (!order) {
    const exists = await Order.exists({
      _id: req.params.orderId,
      business: business._id
    });
    if (!exists) {
      throw new AppError('Order was not found', 404, 'ORDER_NOT_FOUND');
    }
    throw new AppError(
      'A courier can no longer be assigned to this order',
      409,
      'ORDER_COURIER_LOCKED'
    );
  }

  res.json({ success: true, data: { order: order.toMerchantJSON() } });
});
