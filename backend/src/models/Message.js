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

/**
 * The message this one answers, copied when the answer was written.
 *
 * A copy for the same reason the shared product is one: the quote has to stay
 * readable when what it quotes is a hundred messages back, or gone. Only
 * enough of it to recognise which message it was.
 */
const replyToSchema = new mongoose.Schema(
  {
    messageId: { type: String, required: true, trim: true },
    senderType: { type: String, enum: ['customer', 'business'], required: true },
    senderName: { type: String, trim: true, maxlength: 80, default: '' },
    body: { type: String, trim: true, maxlength: 200, default: '' },
    // So a quote of a shared card can say what it was rather than showing an
    // empty line.
    hasProduct: { type: Boolean, default: false }
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
    replyTo: { type: replyToSchema, default: null },
    readAt: { type: Date, default: null }
  },
  { timestamps: true }
);

messageSchema.index({ conversation: 1, createdAt: -1, _id: -1 });

/**
 * The shape the app reads.
 *
 * [bookmarked] is the reader's own mark and is passed in rather than stored
 * here: the same message is bookmarked by one side and not the other, so it
 * cannot be a property of the message itself.
 */
messageSchema.methods.toClientJSON = function toClientJSON(
  viewerType,
  { bookmarked = false } = {}
) {
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
    replyTo: this.replyTo
      ? {
          messageId: this.replyTo.messageId,
          senderType: this.replyTo.senderType,
          senderName: this.replyTo.senderName,
          body: this.replyTo.body,
          hasProduct: this.replyTo.hasProduct,
          // Whether the quote is of something this reader said, which is what
          // the app colours it by.
          isMine: this.replyTo.senderType === viewerType
        }
      : null,
    bookmarked,
    isMine: this.senderType === viewerType,
    readAt: this.readAt,
    createdAt: this.createdAt
  };
};

export const Message = mongoose.model('Message', messageSchema);
