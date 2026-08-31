import crypto from 'node:crypto';

import mongoose from 'mongoose';

import { Business } from '../models/Business.js';
import { Order } from '../models/Order.js';
import { User } from '../models/User.js';
import {
  issueCourierLocationCapability
} from '../policies/courier-location.policy.js';
import {
  canTransitionOwnerOrder,
  courierAssignableStatuses,
  orderStatusGroups as policyStatusGroups,
  orderStatuses as policyStatuses,
  statusGroupFor
} from '../policies/order-status.policy.js';
import {
  buildAtomicInventoryUpdate,
  classifyInventoryConflict,
  inventoryConflictResponse
} from '../policies/checkout-intent.policy.js';
import {
  buildProductWrite,
  PRODUCT_VARIANT_ERRORS
} from '../policies/product.policy.js';
import { paginationParams } from '../policies/query.policy.js';
import { notifyOrderStatus } from '../services/notification.service.js';
import {
  publishOrderTrackingChanged
} from '../realtime/realtime.publisher.js';
import { AppError } from '../utils/AppError.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { normalizeIdentifier, normalizePhone } from '../utils/normalize.js';

// The transition map, the status list, and the group mapping all live in the
// shared policy now; these are lookup views over it.
const orderStatuses = new Set(policyStatuses);
const orderStatusGroups = new Set(policyStatusGroups);

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

// Re-exported so existing importers keep a stable entry point.
export { canTransitionOwnerOrder };

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
  // Deliberately unfiltered: a merchant who hides a product must still see
  // it, or the artboard's "show on the storefront" action could never be
  // reached again. Customer-facing routes filter on isActive themselves.
  const products = [...business.products]
    .sort((left, right) => right.createdAt - left.createdAt)
    .map((product) => business.productToOwnerJSON(product));

  res.json({ success: true, data: { products } });
});

function productWriteOrThrow(body, current = {}) {
  try {
    return buildProductWrite(body, current);
  } catch (error) {
    if (error?.code === PRODUCT_VARIANT_ERRORS.unknownId) {
      throw new AppError(
        'Product variant id is invalid',
        400,
        PRODUCT_VARIANT_ERRORS.unknownId
      );
    }

    throw error;
  }
}

export const createMyBusinessProduct = asyncHandler(async (req, res) => {
  const business = await findOwnedBusiness(req);

  // buildProductWrite returns only contract fields, so nothing from the request
  // body reaches the subdocument unchecked and Mongo assigns the identity.
  business.products.push({
    description: '',
    imageUrl: '',
    imageUrls: [],
    classification: 'new',
    isService: false,
    isActive: true,
    ...productWriteOrThrow(req.body)
  });

  const product = business.products[business.products.length - 1];
  await business.save();

  res.status(201).json({
    success: true,
    data: { product: business.productToOwnerJSON(product) }
  });
});

/** Whether this request is trying to rewrite the product's stock at all. */
function touchesInventory(body) {
  return (
    body.stockQuantity !== undefined ||
    body.unlimitedStock !== undefined ||
    body.variants !== undefined
  );
}

/**
 * Applies a merchant product update whose correctness depends on inventory.
 *
 * The reservation check is NOT performed here and then trusted later - it is a
 * predicate inside the very update MongoDB executes, so a checkout that
 * reserves stock a microsecond after we read the document still causes this
 * write to match nothing. The previous read/check/save shape could not promise
 * that: the observation was true when made and stale when used.
 *
 * Only inventory-touching requests take this path. Name, description, price,
 * discount, images, keywords and activation cannot be corrupted by a release,
 * so they keep the ordinary document save and stay editable throughout.
 */
async function applyInventoryUpdate({ business, product, write, ownerId }) {
  const atomic = buildAtomicInventoryUpdate({
    businessId: business._id,
    ownerId,
    productId: product._id,
    write,
    observedStock: {
      stockQuantity: product.stockQuantity,
      unlimitedStock: product.unlimitedStock
    },
    observedVariants:
      write.variants !== undefined
        ? product.variants
        : undefined
  });

  // `new: true` so the response reports what MongoDB actually stored, never the
  // stale in-memory subdocument this request started from.
  const updated = await Business.findOneAndUpdate(atomic.filter, atomic.update, {
    arrayFilters: atomic.arrayFilters,
    new: true
  });

  if (updated) return updated;

  // The write matched nothing, and the filter has several predicates that could
  // be the reason. Read once more purely to say which - this read authorizes
  // nothing and is followed by no second write, so the CAS above remains the
  // only thing that ever mutates inventory.
  const current = await Business.findOne({
    _id: business._id,
    owner: ownerId
  }).select('+stockReservations');

  const conflict = classifyInventoryConflict({
    business: current,
    product: current?.products?.id(product._id),
    observedStock: {
      stockQuantity: product.stockQuantity,
      unlimitedStock: product.unlimitedStock
    }
  });

  // The message never carries the current stock figure, a reservation id, or
  // anything identifying a customer or their checkout. The mapping lives beside
  // the classifier so the API and its tests cannot describe it differently.
  const failure = inventoryConflictResponse(conflict);

  throw new AppError(failure.message, failure.status, failure.code);
}

export const updateMyBusinessProduct = asyncHandler(async (req, res) => {
  const business = await findOwnedBusiness(req);
  const product = business.products.id(req.params.productId);
  if (!product) {
    throw new AppError('Product not found', 404, 'PRODUCT_NOT_FOUND');
  }

  const write = productWriteOrThrow(req.body, {
    unlimitedStock: product.unlimitedStock,
    stockQuantity: product.stockQuantity,
    variants: product.variants
  });

  if (touchesInventory(req.body)) {
    // Every field of this request goes in one guarded update, so a blocked
    // inventory change cannot leave a description or price behind it applied.
    const updated = await applyInventoryUpdate({
      business,
      product,
      write,
      ownerId: req.user._id
    });
    const stored = updated.products.id(product._id);

    return res.json({
      success: true,
      data: { product: updated.productToOwnerJSON(stored) }
    });
  }

  for (const [field, value] of Object.entries(write)) {
    product[field] = value;
  }
  await business.save();

  res.json({
    success: true,
    data: { product: business.productToOwnerJSON(product) }
  });
});

export const deleteMyBusinessProduct = asyncHandler(async (req, res) => {
  const business = await findOwnedBusiness(req);
  const product = business.products.id(req.params.productId);
  if (!product) {
    throw new AppError('Product not found', 404, 'PRODUCT_NOT_FOUND');
  }

  // The artboard calls this "delete permanently" and offers hiding as a
  // separate action, so this removes the product rather than deactivating
  // it. Nothing breaks downstream: every reader of a product id already
  // handles the product being gone, and an order keeps its own snapshot of
  // what was bought.
  const removed = business.productToOwnerJSON(product);
  product.deleteOne();
  await business.save();

  res.json({ success: true, data: { product: removed } });
});

// The order search the merchant browse artboard offers.
//
// Its placeholder names the order number and the customer name, so those are
// the only two fields matched. The needle is escaped before it reaches Mongo:
// a customer called "a.*b" must not become a wildcard.
export function ownerOrderSearchFilter(query = {}) {
  const value = query.q;

  if (value === undefined || value === null) return null;

  if (Array.isArray(value)) {
    throw new AppError('Order search is invalid', 400, 'INVALID_ORDER_SEARCH');
  }

  const needle = String(value).trim().slice(0, 80);
  if (!needle) return null;

  const escaped = needle.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return [
    { publicId: { $regex: escaped, $options: 'i' } },
    { customerName: { $regex: escaped, $options: 'i' } }
  ];
}

// One escaped, length-bounded needle from a query parameter, or null.
function orderNeedle(value, code) {
  if (value === undefined || value === null) return null;

  if (Array.isArray(value)) {
    throw new AppError('Order search is invalid', 400, code);
  }

  const needle = String(value).trim().slice(0, 80);
  if (!needle) return null;

  return needle.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// The order filter sheet's four fields, as one Mongo filter fragment.
//
// `الرئيسية – 12` asks for an order number and a customer name separately —
// unlike the browse screen's single `q`, which matches either — and for a
// date range around them. Every field is optional and they intersect.
export function ownerOrderFilterFields(query = {}) {
  const filter = {};

  const publicId = orderNeedle(query.orderNumber, 'INVALID_ORDER_NUMBER');
  if (publicId) filter.publicId = { $regex: publicId, $options: 'i' };

  const customer = orderNeedle(query.customerName, 'INVALID_ORDER_CUSTOMER');
  if (customer) filter.customerName = { $regex: customer, $options: 'i' };

  const createdAt = {};
  const from = orderDateBound(query.from, 'INVALID_ORDER_DATE_FROM');
  const to = orderDateBound(query.to, 'INVALID_ORDER_DATE_TO');
  if (from) createdAt.$gte = from;
  // `to` names a day, and a merchant asking for orders "to the 15th" means
  // the whole of the 15th, so the bound runs to the end of that day.
  if (to) createdAt.$lte = new Date(to.getTime() + 86399999);
  if (from || to) filter.createdAt = createdAt;

  return filter;
}

// A calendar day from the sheet's DD.MM.YYYY field, at UTC midnight.
function orderDateBound(value, code) {
  if (value === undefined || value === null || value === '') return null;

  if (Array.isArray(value)) {
    throw new AppError('Order date filter is invalid', 400, code);
  }

  const text = String(value).trim();
  if (!text) return null;

  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
  if (!match) {
    throw new AppError('Order date filter is invalid', 400, code);
  }

  const [year, month, day] = match.slice(1).map(Number);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  if (
    parsed.getUTCFullYear() !== year ||
    parsed.getUTCMonth() !== month - 1 ||
    parsed.getUTCDate() !== day
  ) {
    throw new AppError('Order date filter is invalid', 400, code);
  }

  return parsed;
}

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

  const search = ownerOrderSearchFilter(req.query);
  if (search) filter.$or = search;

  Object.assign(filter, ownerOrderFilterFields(req.query));

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

  if (
    nextStatus === 'delivered' ||
    nextStatus === 'cancelled'
  ) {
    set['courierLocationCapability.tokenHash'] = '';
    set['courierLocationCapability.revokedAt'] =
      changedAt;
    set.courierLocation = null;
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

  publishOrderTrackingChanged({
    recipientIds: [updated.user],
    orderId: updated._id,
    reason: 'order-status-changed'
  });

  await notifyOrderStatus({
    userId: updated.user,
    order: updated,
    status: nextStatus
  });

  res.json({ success: true, data: { order: updated.toMerchantJSON() } });
});

/**
 * How long a merchant must wait before re-sending the same order's status.
 *
 * `إرسال إشعار` is a button a merchant can lean on, and every press lands in a
 * customer's notifications. One a minute is enough to chase a customer who
 * missed the first one and too slow to be a channel to shout down.
 */
export const MANUAL_ORDER_NOTIFY_COOLDOWN_MS = 60_000;

export function manualNotifyRetryAfterMs(lastNotifiedAt, now = new Date()) {
  if (!lastNotifiedAt) return 0;

  const elapsed = now.getTime() - new Date(lastNotifiedAt).getTime();
  if (!Number.isFinite(elapsed) || elapsed >= MANUAL_ORDER_NOTIFY_COOLDOWN_MS) {
    return 0;
  }

  // A clock that moved backwards must not hand out a longer wait than the
  // cooldown itself.
  return Math.min(
    MANUAL_ORDER_NOTIFY_COOLDOWN_MS,
    MANUAL_ORDER_NOTIFY_COOLDOWN_MS - elapsed
  );
}

/**
 * Re-sends the order's CURRENT status to the customer.
 *
 * `تفاصيل الطلب` puts this beside the status control, for the case the status
 * has not changed but the customer has not noticed it. It carries no payload
 * on purpose: the notification says what the server already believes, so a
 * merchant cannot announce a state the order is not in.
 */
export const notifyMyBusinessOrderCustomer = asyncHandler(async (req, res) => {
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

  const retryAfterMs = manualNotifyRetryAfterMs(order.lastManualNotifyAt);
  if (retryAfterMs > 0) {
    throw new AppError(
      'This order was notified moments ago',
      429,
      'ORDER_NOTIFY_COOLDOWN'
    );
  }

  const notifiedAt = new Date();
  const updated = await Order.findOneAndUpdate(
    {
      _id: order._id,
      business: business._id,
      // Same guard the status route uses: two presses that raced must not both
      // send.
      $or: [
        { lastManualNotifyAt: null },
        { lastManualNotifyAt: order.lastManualNotifyAt ?? null }
      ]
    },
    { $set: { lastManualNotifyAt: notifiedAt } },
    { new: true, runValidators: true }
  );
  if (!updated) {
    throw new AppError(
      'This order was notified moments ago',
      429,
      'ORDER_NOTIFY_COOLDOWN'
    );
  }

  await notifyOrderStatus({
    userId: updated.user,
    order: updated,
    status: updated.status
  });

  res.json({ success: true, data: { order: updated.toMerchantJSON() } });
});

/**
 * Courier assignment rotates a narrow, order-scoped location capability.
 *
 * Only the SHA-256 token hash is persisted. The raw credential is returned
 * exactly in this response so the merchant can hand it to the courier flow.
 */
export const updateMyBusinessOrderCourier = asyncHandler(async (req, res) => {
  const business = await findOwnedBusiness(req);
  if (!mongoose.isValidObjectId(req.params.orderId)) {
    throw new AppError('Order id is invalid', 400, 'INVALID_ORDER_ID');
  }

  const capability =
    issueCourierLocationCapability();

  const order = await Order.findOneAndUpdate(
    {
      _id: req.params.orderId,
      business: business._id,
      status: { $in: courierAssignableStatuses }
    },
    {
      $set: {
        courier: {
          name: String(req.body.name).trim(),
          phone: String(req.body.phone ?? '').trim(),
          assignedAt: capability.issuedAt
        },
        courierLocationCapability: {
          tokenHash: capability.tokenHash,
          issuedAt: capability.issuedAt,
          expiresAt: capability.expiresAt,
          revokedAt: null
        },
        courierLocation: null
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

  publishOrderTrackingChanged({
    recipientIds: [order.user],
    orderId: order._id,
    reason: 'courier-location-cleared'
  });

  res.json({
    success: true,
    data: {
      order: order.toMerchantJSON(),
      courierLocationCapability: {
        token: capability.token,
        expiresAt: capability.expiresAt
      }
    }
  });
});

/**
 * Merchant-side kill switch for a leaked, lost or no-longer-needed courier
 * credential. It is deliberately idempotent and also removes the visible
 * latest-location snapshot.
 */
export const revokeMyBusinessOrderCourierLocation =
  asyncHandler(async (req, res) => {
    const business = await findOwnedBusiness(req);

    if (!mongoose.isValidObjectId(req.params.orderId)) {
      throw new AppError(
        'Order id is invalid',
        400,
        'INVALID_ORDER_ID'
      );
    }

    const revokedAt = new Date();

    const order =
      await Order.findOneAndUpdate(
        {
          _id: req.params.orderId,
          business: business._id
        },
        {
          $set: {
            'courierLocationCapability.tokenHash':
              '',
            'courierLocationCapability.revokedAt':
              revokedAt,
            courierLocation: null
          }
        },
        {
          new: true,
          runValidators: true
        }
      );

    if (!order) {
      throw new AppError(
        'Order was not found',
        404,
        'ORDER_NOT_FOUND'
      );
    }

    publishOrderTrackingChanged({
      recipientIds: [order.user],
      orderId: order._id,
      reason: 'courier-location-cleared'
    });

    res.json({
      success: true,
      data: {
        order: order.toMerchantJSON()
      }
    });
  });
