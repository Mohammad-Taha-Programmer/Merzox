import mongoose from 'mongoose';

/**
 * One person refusing to hear from another.
 *
 * A row rather than a flag on either account, because a block belongs to the
 * one who made it: A blocking B says nothing about B blocking A, and either
 * may be true on its own.
 *
 * The pair is the whole record. There is deliberately no reason, no note and
 * no expiry: none of them changes what the app does, and a field that no
 * screen can set or show is a promise the code does not keep.
 */
const userBlockSchema = new mongoose.Schema(
  {
    /** The one who blocked. */
    blocker: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true
    },
    /** The one they no longer wish to hear from. */
    blocked: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true
    }
  },
  { timestamps: true }
);

// Blocking twice is the same block. The unique index makes the write
// idempotent rather than a check that could race with a second tap.
userBlockSchema.index(
  { blocker: 1, blocked: 1 },
  { unique: true, name: 'unique_block_pair' }
);

// The list a reader manages, newest first.
userBlockSchema.index({ blocker: 1, createdAt: -1 });

export const UserBlock = mongoose.model('UserBlock', userBlockSchema);
