import bcrypt from 'bcryptjs';
import mongoose from 'mongoose';
import validator from 'validator';

import { formatBirthDate } from '../policies/birth-date.policy.js';

/**
 * One saved delivery address.
 *
 * Every field is bounded here as well as in the policy: the policy guards the
 * route, and this guards the database, so a write that ever reaches the model
 * by another path still cannot store an unbounded string.
 */
const addressSchema = new mongoose.Schema(
  {
    label: { type: String, trim: true, maxlength: 40, default: '' },
    fullName: { type: String, trim: true, required: true, maxlength: 80 },
    phone: { type: String, trim: true, required: true, maxlength: 20 },
    altPhone: { type: String, trim: true, default: '', maxlength: 20 },
    governorate: { type: String, trim: true, required: true, maxlength: 60 },
    city: { type: String, trim: true, required: true, maxlength: 60 },
    details: { type: String, trim: true, default: '', maxlength: 250 },
    isDefault: { type: Boolean, default: false }
  },
  { _id: true, timestamps: true }
);

const phoneSchema = new mongoose.Schema(
  {
    value: {
      type: String,
      required: true,
      trim: true,
      match: [/^\+?[0-9]{7,15}$/, 'Phone number must be international format']
    },
    label: {
      type: String,
      enum: ['mobile', 'work', 'home', 'fax', 'other'],
      default: 'mobile'
    },
    isPrimary: { type: Boolean, default: false }
  },
  { _id: false }
);

const emailSchema = new mongoose.Schema(
  {
    value: {
      type: String,
      required: true,
      trim: true,
      lowercase: true,
      validate: {
        validator(value) {
          return validator.isEmail(value);
        },
        message: 'Email is invalid'
      }
    },
    label: {
      type: String,
      enum: ['personal', 'work', 'home', 'other'],
      default: 'personal'
    },
    isPrimary: { type: Boolean, default: false },
    verified: { type: Boolean, default: false }
  },
  { _id: false }
);

const permissionConsentSchema = new mongoose.Schema(
  {
    status: {
      type: String,
      enum: ['notAsked', 'granted', 'denied'],
      default: 'notAsked'
    },
    askedAt: { type: Date, default: null },
    respondedAt: { type: Date, default: null }
  },
  { _id: false }
);

const userSchema = new mongoose.Schema(
  {
    name: {
      type: String,
      required: true,
      trim: true,
      minlength: 2,
      maxlength: 80
    },
    nameChangedAt: { type: Date, default: null },
    genderChangedAt: { type: Date, default: null },
    email: {
      type: String,
      trim: true,
      lowercase: true,
      sparse: true,
      unique: true,
      validate: {
        validator(value) {
          return !value || validator.isEmail(value);
        },
        message: 'Email is invalid'
      }
    },
    emailVerified: { type: Boolean, default: false },
    emails: { type: [emailSchema], default: [] },
    phone: {
      type: String,
      trim: true,
      sparse: true,
      unique: true,
      match: [/^\+?[0-9]{7,15}$/, 'Phone number must be international format']
    },
    phones: { type: [phoneSchema], default: [] },
    // The profile's single free-text address. Kept as it was: an account that
    // never opens the address book still has exactly this, and every existing
    // order was placed against it.
    address: {
      type: String,
      trim: true,
      maxlength: 250,
      default: ''
    },
    addresses: { type: [addressSchema], default: [] },
    userType: {
      type: String,
      enum: ['normal', 'business'],
      default: 'normal',
      index: true
    },
    gender: {
      type: String,
      enum: ['male', 'female', 'unspecified'],
      default: 'unspecified'
    },
    // Optional and date-only. Stored at UTC midnight and exposed as
    // `YYYY-MM-DD`; a legacy account without one stays valid and reports null.
    birthDate: {
      type: Date,
      default: null
    },
    passwordHash: {
      type: String,
      required: true,
      select: false
    },
    passwordResetTokenHash: {
      type: String,
      select: false,
      index: true
    },
    passwordResetExpiresAt: {
      type: Date,
      select: false
    },
    authVersion: {
      type: Number,
      default: 0,
      min: 0
    },
    permissions: {
      aiPersonalization: { type: Boolean, default: false },
      location: { type: Boolean, default: false },
      contacts: { type: Boolean, default: false }
    },
    permissionConsents: {
      location: { type: permissionConsentSchema, default: () => ({}) },
      aiPersonalization: { type: permissionConsentSchema, default: () => ({}) },
      contacts: { type: permissionConsentSchema, default: () => ({}) }
    },
    notificationPreferences: {
      productOffers: { type: Boolean, default: true }
    },
    isActive: { type: Boolean, default: true }
  },
  { timestamps: true }
);

userSchema.index({ name: 'text', email: 'text', phone: 'text' });
userSchema.index({ 'emails.value': 1 }, { unique: true, sparse: true });
userSchema.index({ 'phones.value': 1 }, { unique: true, sparse: true });

userSchema.virtual('canChangeName').get(function canChangeName() {
  return !this.nameChangedAt;
});

userSchema.virtual('canChangeGender').get(function canChangeGender() {
  return !this.genderChangedAt;
});

userSchema.methods.setPassword = async function setPassword(password) {
  this.passwordHash = await bcrypt.hash(password, 12);
};

userSchema.methods.verifyPassword = function verifyPassword(password) {
  return bcrypt.compare(password, this.passwordHash);
};

userSchema.methods.toSafeJSON = function toSafeJSON() {
  return {
    id: this._id.toString(),
    name: this.name,
    email: this.email ?? null,
    emailVerified: this.emailVerified,
    emails: this.emails,
    phone: this.phone ?? null,
    phones: this.phones,
    address: this.address,
    addresses: this.addresses.map((entry) => ({
      id: entry._id.toString(),
      label: entry.label,
      fullName: entry.fullName,
      phone: entry.phone,
      altPhone: entry.altPhone,
      governorate: entry.governorate,
      city: entry.city,
      details: entry.details,
      isDefault: entry.isDefault
    })),
    userType: this.userType,
    gender: this.gender,
    // Date-only on the wire. A full ISO timestamp would invite a client-side
    // timezone conversion that shifts the calendar day.
    birthDate: formatBirthDate(this.birthDate),
    permissions: this.permissions,
    permissionConsents: this.permissionConsents,
    canChangeName: this.canChangeName,
    canChangeGender: this.canChangeGender,
    createdAt: this.createdAt,
    updatedAt: this.updatedAt
  };
};

export const User = mongoose.model('User', userSchema);
