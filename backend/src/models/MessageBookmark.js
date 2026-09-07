import mongoose from 'mongoose';

/**
 * One reader's mark on one message.
 *
 * Its own collection rather than a flag on the message, because a message is
 * seen by two people and a mark belongs to one of them. A merchant who marks
 * a customer's question must not put a mark on that customer's screen.
 *
 * The conversation is carried alongside the message so the list of marks can
 * be read, and each one opened, without loading every message behind it.
 */
const messageBookmarkSchema = new mongoose.Schema(
  {
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true
    },
    message: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Message',
      required: true
    },
    conversation: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Conversation',
      required: true,
      index: true
    }
  },
  { timestamps: true }
);

// Marking twice is the same mark. The unique index is what makes the write
// idempotent, so a double tap cannot leave two rows to remove.
messageBookmarkSchema.index(
  { user: 1, message: 1 },
  { unique: true, name: 'unique_bookmark_per_reader' }
);

// The list is read newest first, per reader.
messageBookmarkSchema.index({ user: 1, createdAt: -1 });

export const MessageBookmark = mongoose.model(
  'MessageBookmark',
  messageBookmarkSchema
);
