import mongoose from 'mongoose';

/**
 * A product carried by a message, copied at the moment it was shared.
 *
 * A copy rather than a reference: the card says what was shared on the day it
 * was shared, so a later price change cannot rewrite a conversation and a
 * withdrawn product still leaves the message readable. `productId` and
 * `businessId` are kept so the card can lead to the live product page.
 */
const sharedProductSchema = new mongoose.Schema(
  {
    productId: { type: String, required: true, trim: true },
    businessId: { type: String, required: true, trim: true },
    name: { type: String, trim: true, maxlength: 120, default: '' },
    price: { type: Number, min: 0, default: 0 },
    imageUrl: { type: String, trim: true, maxlength: 1000, default: '' }
  },
  { _id: false }
);

const messageSchema = new mongoose.Schema(
  {
    conversation: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Conversation',
      required: true,
      index: true
    },
    business: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Business',
      required: true,
      index: true
    },
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true
    },
    senderType: {
      type: String,
      enum: ['customer', 'business'],
      required: true
    },
    senderName: { type: String, trim: true, maxlength: 80, default: '' },
    // No longer required on its own: a shared product card is a message
    // without words, and the two cannot both be absent - which the send route
    // enforces, because a schema cannot say "one of these".
    body: {
      type: String,
      trim: true,
      default: '',
      maxlength: 2000
    },
    sharedProduct: { type: sharedProductSchema, default: null },
    readAt: { type: Date, default: null }
  },
  { timestamps: true }
);

messageSchema.index({ conversation: 1, createdAt: -1, _id: -1 });

messageSchema.methods.toClientJSON = function toClientJSON(viewerType) {
  return {
    id: this._id.toString(),
    conversationId: this.conversation.toString(),
    senderType: this.senderType,
    senderName: this.senderName,
    body: this.body,
    sharedProduct: this.sharedProduct
      ? {
          productId: this.sharedProduct.productId,
          businessId: this.sharedProduct.businessId,
          name: this.sharedProduct.name,
          price: this.sharedProduct.price,
          imageUrl: this.sharedProduct.imageUrl
        }
      : null,
    isMine: this.senderType === viewerType,
    readAt: this.readAt,
    createdAt: this.createdAt
  };
};

export const Message = mongoose.model('Message', messageSchema);
