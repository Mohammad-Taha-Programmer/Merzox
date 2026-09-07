import mongoose from 'mongoose';

import {
  REPORT_NOTE_MAX,
  USER_REPORT_REASONS
} from '../policies/user-report.policy.js';

/**
 * One person telling the operator about another.
 *
 * Every report is its own row. Two complaints about the same account are two
 * pieces of testimony about two occasions, and collapsing them into one would
 * throw away the second - which is exactly the thing that shows a pattern.
 *
 * There is deliberately no `status` field. Nothing in this app can change
 * one: reports are read out of the database by whoever runs it, and a column
 * that only ever said `open` would describe the app's own lack of a
 * moderation screen rather than anything about the report.
 */
const userReportSchema = new mongoose.Schema(
  {
    /** The one who reported. */
    reporter: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true
    },
    /** The one they reported. */
    reported: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true
    },
    /**
     * Where it happened.
     *
     * Kept so whoever reads the report can find the thread it is about
     * without asking the reporter what they meant.
     */
    conversation: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Conversation',
      required: true
    },
    reason: {
      type: String,
      required: true,
      enum: USER_REPORT_REASONS
    },
    note: {
      type: String,
      trim: true,
      maxlength: REPORT_NOTE_MAX,
      default: ''
    }
  },
  { timestamps: true }
);

// How the pile is read: everything about one account, newest first.
userReportSchema.index({ reported: 1, createdAt: -1 });

export const UserReport = mongoose.model('UserReport', userReportSchema);
