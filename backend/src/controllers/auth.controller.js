import bcrypt from 'bcryptjs';
import crypto from 'crypto';

import { User } from '../models/User.js';
import { env } from '../config/env.js';
import { AppError } from '../utils/AppError.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { signAccessToken } from '../utils/jwt.js';
import { sendVerificationEmail } from '../services/email.service.js';
import {
  consumePasswordReset,
  requestPasswordReset
} from '../services/password-recovery.service.js';
import {
  normalizeGender,
  normalizeIdentifier,
  normalizePhone
} from '../utils/normalize.js';

function authResponse(user) {
  return {
    token: signAccessToken(user),
    user: user.toSafeJSON()
  };
}

const emailVerificationTtlMs = 1000 * 60 * 60 * 24;

function encryptionKey() {
  return crypto.createHash('sha256').update(env.jwtSecret).digest();
}

function encryptPendingSignup(payload) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', encryptionKey(), iv);
  const encrypted = Buffer.concat([
    cipher.update(JSON.stringify(payload), 'utf8'),
    cipher.final()
  ]);
  const tag = cipher.getAuthTag();

  return [iv, tag, encrypted].map((part) => part.toString('base64url')).join('.');
}

function decryptPendingSignup(token) {
  const [ivPart, tagPart, encryptedPart] = token.split('.');
  if (!ivPart || !tagPart || !encryptedPart) {
    throw new AppError('Verification link is invalid or expired', 400, 'INVALID_VERIFICATION_TOKEN');
  }

  try {
    const decipher = crypto.createDecipheriv(
      'aes-256-gcm',
      encryptionKey(),
      Buffer.from(ivPart, 'base64url')
    );
    decipher.setAuthTag(Buffer.from(tagPart, 'base64url'));

    const decrypted = Buffer.concat([
      decipher.update(Buffer.from(encryptedPart, 'base64url')),
      decipher.final()
    ]);

    return JSON.parse(decrypted.toString('utf8'));
  } catch (_error) {
    throw new AppError('Verification link is invalid or expired', 400, 'INVALID_VERIFICATION_TOKEN');
  }
}

function verificationLink(token) {
  return `${env.publicBaseUrl}/api/v1/auth/verify-email?token=${token}`;
}

export const signup = asyncHandler(async (req, res) => {
  const phone = req.body.phone ? normalizePhone(req.body.phone) : undefined;
  const email = req.body.email ? normalizeIdentifier(req.body.email) : undefined;

  const existingUser = await User.findOne({
    $or: [...(phone ? [{ phone }] : []), ...(email ? [{ email }] : [])]
  });

  if (existingUser) {
    throw new AppError('Account already exists', 409, 'ACCOUNT_EXISTS');
  }

  if (email) {
    const passwordHash = await bcrypt.hash(String(req.body.password), 12);
    const token = encryptPendingSignup({
      name: String(req.body.name).trim(),
      email,
      passwordHash,
      address: String(req.body.address ?? '').trim(),
      userType: 'normal',
      gender: normalizeGender(req.body.gender),
      permissions: req.body.permissions ?? undefined,
      expiresAt: Date.now() + emailVerificationTtlMs
    });
    const link = verificationLink(token);

    const emailResult = await sendVerificationEmail({
      to: email,
      name: String(req.body.name).trim(),
      link
    });

    return res.status(202).json({
      success: true,
      data: {
        requiresEmailVerification: true,
        emailSent: emailResult.sent,
        verificationLink: env.nodeEnv === 'production' ? undefined : link
      }
    });
  }

  const user = new User({
    name: String(req.body.name).trim(),
    phone,
    phones: phone ? [{ value: phone, label: 'mobile', isPrimary: true }] : [],
    address: String(req.body.address ?? '').trim(),
    userType: 'normal',
    gender: normalizeGender(req.body.gender),
    permissions: req.body.permissions ?? undefined,
    emailVerified: true
  });

  await user.setPassword(String(req.body.password));
  await user.save();

  res.status(201).json({
    success: true,
    data: {
      requiresEmailVerification: false,
      user: user.toSafeJSON()
    }
  });
});

export const login = asyncHandler(async (req, res) => {
  const identifier = normalizeIdentifier(req.body.identifier);
  const phoneIdentifier = normalizePhone(req.body.identifier);

  const user = await User.findOne({
    $or: [{ email: identifier }, { phone: phoneIdentifier }]
  }).select('+passwordHash');

  if (!user || !(await user.verifyPassword(String(req.body.password)))) {
    throw new AppError('Invalid login credentials', 401, 'INVALID_CREDENTIALS');
  }

  const loggingInWithEmail = identifier.includes('@');
  if (loggingInWithEmail && user.email && !user.emailVerified) {
    throw new AppError('Please verify your email before logging in', 403, 'EMAIL_NOT_VERIFIED');
  }

  if (!user.isActive) {
    throw new AppError('User account is disabled', 403, 'ACCOUNT_DISABLED');
  }

  res.json({ success: true, data: authResponse(user) });
});

export const me = asyncHandler(async (req, res) => {
  res.json({ success: true, data: { user: req.user.toSafeJSON() } });
});

export const verifyEmail = asyncHandler(async (req, res) => {
  const token = String(req.query.token ?? '');
  if (!token) {
    throw new AppError('Verification token is required', 400, 'INVALID_VERIFICATION_TOKEN');
  }

  const pendingSignup = decryptPendingSignup(token);
  if (!pendingSignup.expiresAt || pendingSignup.expiresAt < Date.now()) {
    throw new AppError('Verification link is invalid or expired', 400, 'INVALID_VERIFICATION_TOKEN');
  }

  const existingUser = await User.findOne({ email: pendingSignup.email });
  if (existingUser) {
    throw new AppError('Account already exists', 409, 'ACCOUNT_EXISTS');
  }

  const user = new User({
    name: pendingSignup.name,
    email: pendingSignup.email,
    emails: [
      {
        value: pendingSignup.email,
        label: 'personal',
        isPrimary: true,
        verified: true
      }
    ],
    address: pendingSignup.address ?? '',
    userType: 'normal',
    gender: normalizeGender(pendingSignup.gender),
    permissions: pendingSignup.permissions ?? undefined,
    emailVerified: true,
    passwordHash: pendingSignup.passwordHash
  });

  await user.save();

  res.json({ success: true, data: { message: 'Email verified. You can now log in.' } });
});

export const forgotPassword = asyncHandler(async (req, res) => {
  const email = String(req.body.email).trim().toLowerCase();

  // Recovery work is deliberately decoupled from the public response so a
  // caller cannot distinguish account existence from database/SMTP latency.
  // requestPasswordReset owns and suppresses its operational failures.
  void requestPasswordReset({ email });

  res.status(202).json({
    success: true,
    data: {
      message:
        'If an eligible account exists, password reset instructions will be sent.'
    }
  });
});

export const resetPassword = asyncHandler(async (req, res) => {
  await consumePasswordReset({
    token: req.body.token,
    newPassword: req.body.newPassword
  });

  res.json({
    success: true,
    data: {
      message: 'Password reset successful. You can now log in.'
    }
  });
});

export const logout = asyncHandler(async (_req, res) => {
  res.json({ success: true, data: { message: 'Logged out' } });
});
