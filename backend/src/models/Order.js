import crypto from 'node:crypto';

import mongoose from 'mongoose';

import {
  canChangeDeliveryAddress,
  canCustomerCancel,
  canReviewOrder
} from '../policies/order-status.policy.js';
import { PRODUCT_LIMITS } from '../policies/product.policy.js';
import {
  isCourierLocationSnapshotVisible
} from '../policies/courier-location.policy.js';

const orderItemSchema = new mongoose.Schema(
  {
    productId: {
      type: mongoose.Schema.Types.ObjectId,
      required: true
    },
    // Stable identity of the purchased variant. Null means a simple product.
    variantId: { type: mongoose.Schema.Types.ObjectId, default: null },
    name: { type: String, required: true, trim: true, maxlength: 120 },
    imageUrl: { type: String, trim: true, maxlength: 1000, default: '' },
    unitPrice: { type: Number, required: true, min: 0 },
    quantity: { type: Number, required: true, min: 1, max: 100 },
    // Historical display snapshot; identity lives in variantId.
    variant: {
      type: String,
      trim: true,
      maxlength: PRODUCT_LIMITS.variantLabelMax,
      default: ''
    }
  },
  { _id: false }
);

const statusHistorySchema = new mongoose.Schema(
  {
    status: {
      type: String,
      required: true,
      enum: [
        'pending',
        'confirmed',
        'preparing',
        'outForDelivery',
        'delivered',
        'cancelled'
      ]
    },
    changedAt: { type: Date, default: Date.now },
    note: { type: String, trim: true, maxlength: 250, default: '' }
  },
  { _id: false }
);

const courierSchema = new mongoose.Schema(
  {
    name: { type: String, trim: true, maxlength: 80, default: '' },
    phone: { type: String, trim: true, maxlength: 20, default: '' },
    assignedAt: { type: Date, default: null }
  },
  { _id: false }
);

const courierLocationCapabilitySchema = new mongoose.Schema(
  {
    tokenHash: {
      type: String,
      maxlength: 64,
      default: '',
      select: false
    },
    issuedAt: { type: Date, default: null },
    expiresAt: { type: Date, default: null },
    revokedAt: { type: Date, default: null }
  },
  { _id: false }
);

const courierLocationSchema = new mongoose.Schema(
  {
    latitude: {
      type: Number,
      min: -90,
      max: 90,
      default: null
    },
    longitude: {
      type: Number,
      min: -180,
      max: 180,
      default: null
    },
    accuracy: {
      type: Number,
      min: 0,
      max: 10000,
      default: null
    },
    capturedAt: { type: Date, default: null },
    receivedAt: { type: Date, default: null }
  },
  { _id: false }
);

function createPublicId() {
  const timePart = Date.now().toString(36).toUpperCase();
  const randomPart = crypto.randomBytes(4).toString('hex').toUpperCase();
  return `MX-${timePart}-${randomPart}`;
}

const orderSchema = new mongoose.Schema(
  {
    publicId: {
      type: String,
      required: true,
      unique: true,
      index: true,
      default: createPublicId
    },
    clientOrderId: { type: String, trim: true, maxlength: 80 },
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true
    },
    customerName: { type: String, trim: true, maxlength: 80, default: '' },
    customerPhone: { type: String, trim: true, maxlength: 20, default: '' },
    business: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Business',
      required: true,
      index: true
    },
    businessName: { type: String, required: true, trim: true, maxlength: 120 },
    businessAddress: { type: String, trim: true, maxlength: 250, default: '' },
    items: {
      type: [orderItemSchema],
      required: true,
      validate: {
        validator(value) {
          return value.length > 0 && value.length <= 50;
        },
        message: 'An order must contain between 1 and 50 items'
      }
    },
    subtotal: { type: Number, required: true, min: 0 },
    deliveryFee: { type: Number, required: true, min: 0, default: 10 },
    // Which tier produced deliveryFee. Existing orders predate the
    // choice and read back as the standard one they were charged.
    deliveryOption: {
      type: String,
      enum: ['standard', 'express'],
      default: 'standard'
    },
    total: { type: Number, required: true, min: 0 },
    currency: { type: String, enum: ['ILS'], default: 'ILS' },
    deliveryAddress: {
      type: String,
      required: true,
      trim: true,
      maxlength: 250
    },
    paymentMethod: {
      type: String,
      enum: ['cash', 'card', 'bankTransfer', 'assisted'],
      default: 'cash'
    },
    status: {
      type: String,
      enum: [
        'pending',
        'confirmed',
        'preparing',
        'outForDelivery',
        'delivered',
        'cancelled'
      ],
      default: 'pending',
      index: true
    },
    statusGroup: {
      type: String,
      enum: ['current', 'completed', 'cancelled'],
      default: 'current',
      index: true
    },
    statusHistory: {
      type: [statusHistorySchema],
      default: () => [{ status: 'pending', changedAt: new Date() }]
    },
    cancellationReason: { type: String, trim: true, maxlength: 250, default: '' },
    cancelledAt: { type: Date, default: null },
    deliveredAt: { type: Date, default: null },
    courier: { type: courierSchema, default: () => ({}) },
    courierLocationCapability: {
      type: courierLocationCapabilitySchema,
      default: () => ({})
    },
    courierLocation: {
      type: courierLocationSchema,
      default: null
    }
  },
  { timestamps: true }
);

orderSchema.index({ user: 1, statusGroup: 1, createdAt: -1 });
orderSchema.index({ business: 1, status: 1, createdAt: -1 });
orderSchema.index({ business: 1, statusGroup: 1, createdAt: -1 });
orderSchema.index(
  { user: 1, clientOrderId: 1 },
  {
    unique: true,
    partialFilterExpression: { clientOrderId: { $type: 'string' } }
  }
);

/**
 * The tracking view collapses the six stored statuses onto the four steps the
 * design shows, so the timeline is derived here once instead of in each client.
 */
const trackingSteps = ['placed', 'preparing', 'outForDelivery', 'delivered'];
const statusToStep = new Map([
  ['pending', 'placed'],
  ['confirmed', 'placed'],
  ['preparing', 'preparing'],
  ['outForDelivery', 'outForDelivery'],
  ['delivered', 'delivered']
]);

orderSchema.methods.courierJSON = function courierJSON() {
  const courier = this.courier ?? {};
  return {
    name: courier.name ?? '',
    phone: courier.phone ?? '',
    assignedAt: courier.assignedAt ?? null
  };
};

orderSchema.methods.courierLocationJSON =
  function courierLocationJSON(
    { now = new Date() } = {}
  ) {
    const capability =
      this.courierLocationCapability ?? {};

    const location =
      this.courierLocation;

    if (
      !isCourierLocationSnapshotVisible(
        {
          status: this.status,
          capability,
          location
        },
        { now }
      )
    ) {
      return null;
    }

    return {
      latitude: location.latitude,
      longitude: location.longitude,
      accuracy:
        Number.isFinite(location.accuracy)
          ? location.accuracy
          : null,
      capturedAt: location.capturedAt,
      receivedAt: location.receivedAt,
      capabilityExpiresAt: capability.expiresAt
    };
  };

orderSchema.methods.trackingJSON = function trackingJSON() {
  const reachedAt = new Map();

  for (const entry of this.statusHistory ?? []) {
    const step = statusToStep.get(entry.status);
    if (step && !reachedAt.has(step)) {
      reachedAt.set(step, entry.changedAt);
    }
  }

  const currentStep = statusToStep.get(this.status) ?? 'placed';
  const currentIndex = trackingSteps.indexOf(currentStep);

  return {
    isCancelled: this.status === 'cancelled',
    currentStep: this.status === 'cancelled' ? '' : currentStep,
    currentIndex: this.status === 'cancelled' ? -1 : currentIndex,
    steps: trackingSteps.map((step, index) => ({
      step,
      reachedAt: reachedAt.get(step) ?? null,
      isReached: this.status !== 'cancelled' && index <= currentIndex
    })),
    courier: this.courierJSON(),
    courierLocation: this.courierLocationJSON(),
    canCancel: canCustomerCancel(this.status),
    canChangeAddress: canChangeDeliveryAddress(this.status),
    canReview: canReviewOrder(this.status)
  };
};

orderSchema.methods.toClientJSON = function toClientJSON() {
  return {
    id: this._id.toString(),
    publicId: this.publicId,
    business: {
      id: this.business.toString(),
      name: this.businessName,
      address: this.businessAddress
    },
    items: this.items.map((item) => ({
      productId: item.productId.toString(),
      variantId: item.variantId ? item.variantId.toString() : null,
      name: item.name,
      imageUrl: item.imageUrl,
      unitPrice: item.unitPrice,
      quantity: item.quantity,
      variant: item.variant
    })),
    subtotal: this.subtotal,
    deliveryFee: this.deliveryFee,
    deliveryOption: this.deliveryOption ?? 'standard',
    total: this.total,
    currency: this.currency,
    deliveryAddress: this.deliveryAddress,
    paymentMethod: this.paymentMethod,
    status: this.status,
    statusGroup: this.statusGroup,
    statusHistory: this.statusHistory,
    cancellationReason: this.cancellationReason,
    cancelledAt: this.cancelledAt,
    deliveredAt: this.deliveredAt,
    courier: this.courierJSON(),
    createdAt: this.createdAt,
    updatedAt: this.updatedAt,
    tracking: this.trackingJSON()
  };
};

orderSchema.methods.toMerchantJSON = function toMerchantJSON() {
  return {
    id: this._id.toString(),
    publicId: this.publicId,
    customerName: this.customerName,
    customerPhone: this.customerPhone,
    items: this.items.map((item) => ({
      productId: item.productId.toString(),
      variantId: item.variantId ? item.variantId.toString() : null,
      name: item.name,
      imageUrl: item.imageUrl,
      unitPrice: item.unitPrice,
      quantity: item.quantity,
      variant: item.variant
    })),
    subtotal: this.subtotal,
    deliveryFee: this.deliveryFee,
    deliveryOption: this.deliveryOption ?? 'standard',
    total: this.total,
    currency: this.currency,
    deliveryAddress: this.deliveryAddress,
    paymentMethod: this.paymentMethod,
    status: this.status,
    statusGroup: this.statusGroup,
    statusHistory: this.statusHistory,
    cancellationReason: this.cancellationReason,
    cancelledAt: this.cancelledAt,
    deliveredAt: this.deliveredAt,
    courier: this.courierJSON(),
    createdAt: this.createdAt,
    updatedAt: this.updatedAt,
    tracking: this.trackingJSON()
  };
};

export const Order = mongoose.model('Order', orderSchema);
