import mongoose from 'mongoose';

import {
  PUSH_PLATFORMS,
  PUSH_TARGET_KINDS,
  PUSH_TARGET_MAX_LENGTH,
  PUSH_TARGET_MIN_LENGTH
} from '../policies/push-registration.policy.js';

const pushRegistrationSchema = new mongoose.Schema(
  {
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true
    },
    targetKind: {
      type: String,
      enum: PUSH_TARGET_KINDS,
      required: true
    },
    target: {
      type: String,
      required: true,
      trim: true,
      minlength: PUSH_TARGET_MIN_LENGTH,
      maxlength: PUSH_TARGET_MAX_LENGTH,
      select: false
    },
    platform: {
      type: String,
      enum: PUSH_PLATFORMS,
      required: true
    },
    lastSeenAt: {
      type: Date,
      required: true,
      default: Date.now
    }
  },
  { timestamps: true }
);

/**
 * One FCM target may belong to only one authenticated Merzox account at a
 * time. Registering the same target after an account switch transfers the
 * existing record rather than allowing the old account to keep receiving it.
 */
pushRegistrationSchema.index(
  { targetKind: 1, target: 1 },
  {
    unique: true,
    name: 'unique_push_target'
  }
);

pushRegistrationSchema.index(
  { user: 1, updatedAt: -1, _id: -1 },
  { name: 'push_registrations_by_user' }
);

pushRegistrationSchema.index(
  { lastSeenAt: 1 },
  { name: 'push_registration_freshness' }
);

export const PushRegistration = mongoose.model(
  'PushRegistration',
  pushRegistrationSchema
);
