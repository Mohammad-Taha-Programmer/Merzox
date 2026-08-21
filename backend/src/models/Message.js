import mongoose from 'mongoose';

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
    body: {
      type: String,
      required: true,
      trim: true,
      minlength: 1,
      maxlength: 2000
    },
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
    isMine: this.senderType === viewerType,
    readAt: this.readAt,
    createdAt: this.createdAt
  };
};

export const Message = mongoose.model('Message', messageSchema);
