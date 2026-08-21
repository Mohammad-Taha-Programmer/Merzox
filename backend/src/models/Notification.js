import mongoose from 'mongoose';

export const notificationTypes = [
  'orderPlaced',
  'orderStatus',
  'orderCancelled',
  'newMessage',
  'newReview'
];

const notificationSchema = new mongoose.Schema(
  {
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true
    },
    audience: {
      type: String,
      enum: ['customer', 'business'],
      required: true,
      index: true
    },
    business: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Business',
      default: null
    },
    type: { type: String, enum: notificationTypes, required: true },
    title: { type: String, trim: true, maxlength: 120, default: '' },
    body: { type: String, trim: true, maxlength: 400, default: '' },
    data: {
      type: mongoose.Schema.Types.Mixed,
      default: () => ({})
    },
    readAt: { type: Date, default: null }
  },
  { timestamps: true }
);

notificationSchema.index({ user: 1, audience: 1, createdAt: -1, _id: -1 });
notificationSchema.index({ user: 1, audience: 1, readAt: 1 });

notificationSchema.methods.toClientJSON = function toClientJSON() {
  return {
    id: this._id.toString(),
    type: this.type,
    title: this.title,
    body: this.body,
    data: this.data ?? {},
    isRead: this.readAt !== null,
    readAt: this.readAt,
    createdAt: this.createdAt
  };
};

export const Notification = mongoose.model('Notification', notificationSchema);
