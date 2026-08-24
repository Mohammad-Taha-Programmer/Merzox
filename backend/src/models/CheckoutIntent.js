import mongoose from 'mongoose';

/**
 * The durable record of one semantic checkout attempt.
 *
 * MongoDB gives single-document atomicity, not cross-collection atomicity. The
 * business stock decrement and the order document are two separate writes, so a
 * process that dies between them would otherwise leave inventory consumed with
 * nothing on disk explaining why. This collection is that explanation: it is
 * written BEFORE any stock can be touched, and every later phase transition is
 * a single conditional document update.
 *
 * It is deliberately a separate collection rather than a provisional `Order`.
 * An unfinished checkout must never be reachable by a customer listing, a
 * merchant listing, a dashboard count, or a tracking endpoint, and the surest
 * way to guarantee that is for it not to be an order at all. Nothing here is
 * ever serialized to a client.
 *
 * `phase` is INTERNAL. It is unrelated to the public delivery status
 * (pending / confirmed / preparing / outForDelivery / delivered / cancelled)
 * and must never be mixed into it.
 */
export const checkoutPhases = [
  /** Durable identity exists. No inventory has been touched yet. */
  'prepared',
  /** Finite inventory has been consumed exactly once, order not yet written. */
  'reserved',
  /**
   * A worker has claimed the exclusive right to write this checkout's order.
   * No reconciler may refund inventory while this claim stands and is fresh.
   */
  'finalizing',
  /**
   * A worker has claimed the exclusive right to give this reservation back.
   * No order may be created for this checkout once the claim is taken.
   */
  'releasing',
  /** The order exists and is customer-visible. Terminal. */
  'finalized',
  /** The reservation was rolled back exactly once. Terminal. */
  'released'
];

const intentLineSchema = new mongoose.Schema(
  {
    productId: { type: mongoose.Schema.Types.ObjectId, required: true },
    // Optional for legacy/simple products. Variant subdocuments are owned by
    // Business, so this is an identity snapshot rather than a model ref.
    variantId: { type: mongoose.Schema.Types.ObjectId, default: null },
    quantity: { type: Number, required: true, min: 1 },
    /** Only finite lines ever consumed stock, so only they can be released. */
    finite: { type: Boolean, required: true }
  },
  { _id: false }
);

const checkoutIntentSchema = new mongoose.Schema(
  {
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true
    },
    clientOrderId: { type: String, required: true, trim: true, maxlength: 80 },

    /**
     * A hash of the canonical customer-controlled request. Reusing a key with a
     * different basket is a client bug, not a retry, and is refused rather than
     * silently answered with the first order.
     */
    fingerprint: { type: String, required: true },

    business: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Business',
      required: true
    },

    phase: {
      type: String,
      required: true,
      enum: checkoutPhases,
      default: 'prepared'
    },
    reservationFence: {
      type: Number,
      default: 0,
      min: 0
    },
    /** The exact reservation, so a release can only give back what it took. */
    lines: { type: [intentLineSchema], default: [] },

    /**
     * The fencing token of the claim that currently owns this checkout.
     *
     * A lease says WHEN a claim may be taken over; this says WHOSE it is. Every
     * decisive write is conditional on it, so a worker that stalled past the
     * lease cannot land a result under the claim that replaced it.
     */
    claimToken: {
      type: mongoose.Schema.Types.ObjectId,
      default: null
    },

    /**
     * Everything needed to write this checkout's order, frozen at the instant
     * the finalization decision was made.
     *
     * It exists so a crash between "finalizing" and `Order.create` is
     * recoverable by FINISHING the order rather than refunding stock the
     * decision already sold. Recovery must never re-derive prices from the
     * merchant's current catalog: the historical order price is the one
     * committed here.
     *
     * Deliberately `select: false` and deliberately Mixed - it is an internal
     * verbatim copy of a server-built draft, never a customer- or
     * merchant-facing shape, and nothing serializes it to anybody.
     */
    finalization: {
      type: mongoose.Schema.Types.Mixed,
      default: null,
      select: false
    },

    /** Set once, when the order becomes customer-visible. */
    order: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Order',
      default: null
    },

    /** The stable code a terminal failure resolves to, for a later retry. */
    failureCode: { type: String, default: null }
  },
  { timestamps: true }
);

/**
 * The idempotency identity. Unique, so two concurrent requests carrying the
 * same key cannot both create an intent - exactly one wins the upsert and does
 * the work, and the other converges on it.
 */
checkoutIntentSchema.index({ user: 1, clientOrderId: 1 }, { unique: true });

export const CheckoutIntent = mongoose.model(
  'CheckoutIntent',
  checkoutIntentSchema
);
