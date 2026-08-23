import bcrypt from 'bcryptjs';
import crypto from 'crypto';

import { User } from '../models/User.js';
import { AppError } from '../utils/AppError.js';
import { sendPasswordResetEmail } from './email.service.js';

export const PASSWORD_RESET_TTL_MINUTES = 30;
export const PASSWORD_RESET_TTL_MS =
  PASSWORD_RESET_TTL_MINUTES * 60 * 1000;

const PASSWORD_RESET_TOKEN_BYTES = 32;

export function createPasswordResetToken() {
  return crypto.randomBytes(PASSWORD_RESET_TOKEN_BYTES).toString('base64url');
}

export function hashPasswordResetToken(token) {
  return crypto
    .createHash('sha256')
    .update(String(token))
    .digest('hex');
}

export function passwordResetExpiresAt(now = Date.now()) {
  return new Date(Number(now) + PASSWORD_RESET_TTL_MS);
}

async function revokePasswordResetToken({
  UserModel,
  userId,
  tokenHash
}) {
  await UserModel.updateOne(
    {
      _id: userId,
      passwordResetTokenHash: tokenHash
    },
    {
      $unset: {
        passwordResetTokenHash: '',
        passwordResetExpiresAt: ''
      }
    }
  );
}

/**
 * Starts a password-reset request without revealing whether the email belongs
 * to an account.
 *
 * The function intentionally returns no account/delivery/token information.
 * Operational failures after a syntactically valid request are also swallowed
 * behind the same public response. Logs never contain the email or raw token.
 */
export async function requestPasswordReset({
  email,
  now = Date.now(),
  UserModel = User,
  sendEmail = sendPasswordResetEmail
}) {
  let userId;
  let tokenHash;

  try {
    const user = await UserModel.findOne({
      email,
      emailVerified: true,
      isActive: true
    });

    if (!user) {
      return;
    }

    userId = user._id;

    const token = createPasswordResetToken();
    tokenHash = hashPasswordResetToken(token);
    const expiresAt = passwordResetExpiresAt(now);

    await UserModel.updateOne(
      { _id: userId },
      {
        $set: {
          passwordResetTokenHash: tokenHash,
          passwordResetExpiresAt: expiresAt
        }
      }
    );

    const delivery = await sendEmail({
      to: user.email,
      token,
      expiresInMinutes: PASSWORD_RESET_TTL_MINUTES
    });

    if (!delivery?.sent) {
      await revokePasswordResetToken({
        UserModel,
        userId,
        tokenHash
      });
    }
  } catch (_error) {
    if (userId && tokenHash) {
      try {
        await revokePasswordResetToken({
          UserModel,
          userId,
          tokenHash
        });
      } catch (_revokeError) {
        // Public behavior must remain non-enumerating even if cleanup fails.
      }
    }

    console.warn('Password reset request could not be completed');
  }
}

/**
 * Atomically consumes one unexpired reset token.
 *
 * Hashing the new password before the lookup also avoids giving an obviously
 * cheaper path to a caller merely because their syntactically-valid token is
 * unknown. The MongoDB predicate and $unset make one token single-use.
 */
export async function consumePasswordReset({
  token,
  newPassword,
  now = Date.now(),
  UserModel = User,
  hashPassword = bcrypt.hash
}) {
  const tokenHash = hashPasswordResetToken(token);
  const passwordHash = await hashPassword(String(newPassword), 12);

  const user = await UserModel.findOneAndUpdate(
    {
      passwordResetTokenHash: tokenHash,
      passwordResetExpiresAt: { $gt: new Date(Number(now)) },
      isActive: true
    },
    {
      $set: {
        passwordHash
      },
      $inc: {
        authVersion: 1
      },
      $unset: {
        passwordResetTokenHash: '',
        passwordResetExpiresAt: ''
      }
    },
    {
      new: true
    }
  );

  if (!user) {
    throw new AppError(
      'Password reset token is invalid or expired',
      400,
      'INVALID_PASSWORD_RESET_TOKEN'
    );
  }

  return user;
}
