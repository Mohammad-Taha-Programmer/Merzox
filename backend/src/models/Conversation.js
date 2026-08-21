import mongoose from 'mongoose';

const lastMessageSchema = new mongoose.Schema(
  {
    body: { type: String, trim: true, maxlength: 2000, default: '' },
    senderType: {
      type: String,
      enum: ['customer', 'business'],
      default: 'customer'
    },
    sentAt: { type: Date, default: null }
  },
  { _id: false }
);

const conversationSchema = new mongoose.Schema(
  {
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true
    },
    userName: { type: String, trim: true, maxlength: 80, default: '' },
    business: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Business',
      required: true,
      index: true
    },
    businessName: { type: String, required: true, trim: true, maxlength: 120 },
    businessLogoUrl: { type: String, trim: true, maxlength: 1000, default: '' },
    lastMessage: { type: lastMessageSchema, default: () => ({}) },
    unreadForUser: { type: Number, default: 0, min: 0 },
    unreadForBusiness: { type: Number, default: 0, min: 0 },
    messageCount: { type: Number, default: 0, min: 0 },
    isActive: { type: Boolean, default: true }
  },
  { timestamps: true }
);

conversationSchema.index(
  { user: 1, business: 1 },
  { unique: true, name: 'unique_conversation_per_user_business' }
);
conversationSchema.index({ user: 1, updatedAt: -1 });
conversationSchema.index({ business: 1, updatedAt: -1 });

function lastMessageJSON(conversation) {
  const last = conversation.lastMessage;
  if (!last || !last.sentAt) {
    return { body: '', senderType: 'customer', sentAt: null };
  }

  return {
    body: last.body,
    senderType: last.senderType,
    sentAt: last.sentAt
  };
}

conversationSchema.methods.toCustomerJSON = function toCustomerJSON() {
  return {
    id: this._id.toString(),
    business: {
      id: this.business.toString(),
      name: this.businessName,
      logoUrl: this.businessLogoUrl
    },
    title: this.businessName,
    avatarUrl: this.businessLogoUrl,
    lastMessage: lastMessageJSON(this),
    unreadCount: this.unreadForUser,
    messageCount: this.messageCount,
    createdAt: this.createdAt,
    updatedAt: this.updatedAt
  };
};

conversationSchema.methods.toMerchantJSON = function toMerchantJSON() {
  return {
    id: this._id.toString(),
    customer: {
      id: this.user.toString(),
      name: this.userName
    },
    title: this.userName,
    avatarUrl: '',
    lastMessage: lastMessageJSON(this),
    unreadCount: this.unreadForBusiness,
    messageCount: this.messageCount,
    createdAt: this.createdAt,
    updatedAt: this.updatedAt
  };
};

export const Conversation = mongoose.model('Conversation', conversationSchema);
