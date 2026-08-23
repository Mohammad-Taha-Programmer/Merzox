import assert from 'node:assert/strict';
import test from 'node:test';

import { User } from '../src/models/User.js';
import {
  consumePasswordReset,
  createPasswordResetToken,
  hashPasswordResetToken,
  PASSWORD_RESET_TTL_MS,
  requestPasswordReset
} from '../src/services/password-recovery.service.js';
import {
  validateForgotPassword,
  validateResetPassword
} from '../src/middleware/validate.js';
import { isAccessTokenCurrent } from '../src/utils/jwt.js';
import {
  FORGOT_PASSWORD_RATE_LIMIT_MAX,
  PASSWORD_RECOVERY_RATE_LIMIT_WINDOW_MS,
  RESET_PASSWORD_RATE_LIMIT_MAX
} from '../src/middleware/security.js';

function runMiddleware(middleware, body) {
  let nextCalled = false;

  middleware(
    { body },
    {},
    () => {
      nextCalled = true;
    }
  );

  return nextCalled;
}

async function withoutWarnings(callback) {
  const originalWarn = console.warn;
  console.warn = () => {};

  try {
    return await callback();
  } finally {
    console.warn = originalWarn;
  }
}

test('password recovery has endpoint-specific abuse limits', () => {
  assert.equal(
    PASSWORD_RECOVERY_RATE_LIMIT_WINDOW_MS,
    15 * 60 * 1000
  );
  assert.equal(FORGOT_PASSWORD_RATE_LIMIT_MAX, 5);
  assert.equal(RESET_PASSWORD_RATE_LIMIT_MAX, 20);
});

test('password reset tokens are random and only their SHA-256 digest is stable', () => {
  const first = createPasswordResetToken();
  const second = createPasswordResetToken();

  assert.match(first, /^[A-Za-z0-9_-]{43}$/);
  assert.match(second, /^[A-Za-z0-9_-]{43}$/);
  assert.notEqual(first, second);

  const digest = hashPasswordResetToken(first);

  assert.match(digest, /^[a-f0-9]{64}$/);
  assert.notEqual(digest, first);
  assert.equal(digest, hashPasswordResetToken(first));
});

test('User stores password reset authority outside its public projection', () => {
  assert.equal(
    User.schema.path('passwordResetTokenHash').options.select,
    false
  );
  assert.equal(
    User.schema.path('passwordResetExpiresAt').options.select,
    false
  );

  const user = new User({
    name: 'Recovery User',
    email: 'recovery@example.com',
    emailVerified: true,
    passwordHash: 'not-a-real-hash',
    passwordResetTokenHash: 'secret-digest',
    passwordResetExpiresAt: new Date(Date.now() + 60000)
  });

  const safe = user.toSafeJSON();

  assert.equal(
    Object.prototype.hasOwnProperty.call(
      safe,
      'passwordResetTokenHash'
    ),
    false
  );
  assert.equal(
    Object.prototype.hasOwnProperty.call(
      safe,
      'passwordResetExpiresAt'
    ),
    false
  );
  assert.equal(
    Object.prototype.hasOwnProperty.call(safe, 'passwordHash'),
    false
  );
});

test('forgot-password lookup is restricted to active verified email ownership', async () => {
  const fixedNow = 1_800_000_000_000;
  const updateCalls = [];
  let lookupFilter;
  let delivered;

  const user = {
    _id: 'user-1',
    name: 'Owner',
    email: 'owner@example.com'
  };

  const UserModel = {
    async findOne(filter) {
      lookupFilter = filter;
      return user;
    },

    async updateOne(filter, update) {
      updateCalls.push({ filter, update });
      return { modifiedCount: 1 };
    }
  };

  const result = await requestPasswordReset({
    email: 'owner@example.com',
    now: fixedNow,
    UserModel,
    sendEmail: async (payload) => {
      delivered = payload;
      return { sent: true };
    }
  });

  assert.equal(result, undefined);
  assert.deepEqual(lookupFilter, {
    email: 'owner@example.com',
    emailVerified: true,
    isActive: true
  });

  assert.equal(updateCalls.length, 1);
  assert.deepEqual(updateCalls[0].filter, { _id: 'user-1' });

  const stored =
    updateCalls[0].update.$set.passwordResetTokenHash;
  const expiresAt =
    updateCalls[0].update.$set.passwordResetExpiresAt;

  assert.equal(
    stored,
    hashPasswordResetToken(delivered.token)
  );
  assert.notEqual(stored, delivered.token);
  assert.equal(
    expiresAt.getTime(),
    fixedNow + PASSWORD_RESET_TTL_MS
  );
  assert.equal(delivered.to, 'owner@example.com');
  assert.equal(typeof delivered.token, 'string');
});

test('forgot-password is non-enumerating when no eligible account exists', async () => {
  let updateCalled = false;
  let emailCalled = false;

  const UserModel = {
    async findOne() {
      return null;
    },

    async updateOne() {
      updateCalled = true;
    }
  };

  const result = await requestPasswordReset({
    email: 'missing@example.com',
    UserModel,
    sendEmail: async () => {
      emailCalled = true;
      return { sent: true };
    }
  });

  assert.equal(result, undefined);
  assert.equal(updateCalled, false);
  assert.equal(emailCalled, false);
});

test('forgot-password hides database failures behind the same public behavior', async () => {
  await withoutWarnings(async () => {
    const result = await requestPasswordReset({
      email: 'unknown@example.com',
      UserModel: {
        async findOne() {
          throw new Error('database detail must not escape');
        }
      },
      sendEmail: async () => {
        throw new Error('must not be reached');
      }
    });

    assert.equal(result, undefined);
  });
});

test('an undelivered reset email revokes the exact generated authority', async () => {
  const updateCalls = [];

  const UserModel = {
    async findOne() {
      return {
        _id: 'user-2',
        email: 'owner@example.com'
      };
    },

    async updateOne(filter, update) {
      updateCalls.push({ filter, update });
      return { modifiedCount: 1 };
    }
  };

  await requestPasswordReset({
    email: 'owner@example.com',
    UserModel,
    sendEmail: async () => ({ sent: false })
  });

  assert.equal(updateCalls.length, 2);

  const createdHash =
    updateCalls[0].update.$set.passwordResetTokenHash;

  assert.deepEqual(updateCalls[1], {
    filter: {
      _id: 'user-2',
      passwordResetTokenHash: createdHash
    },
    update: {
      $unset: {
        passwordResetTokenHash: '',
        passwordResetExpiresAt: ''
      }
    }
  });
});

test('reset consumes the hash and expiry in one atomic write', async () => {
  const fixedNow = 1_800_000_000_000;
  const token = 'A'.repeat(43);
  let operation;

  const user = { _id: 'user-3' };

  const UserModel = {
    async findOneAndUpdate(filter, update, options) {
      operation = { filter, update, options };
      return user;
    }
  };

  const result = await consumePasswordReset({
    token,
    newPassword: 'new-secret',
    now: fixedNow,
    UserModel,
    hashPassword: async (password, rounds) => {
      assert.equal(password, 'new-secret');
      assert.equal(rounds, 12);
      return 'new-password-hash';
    }
  });

  assert.equal(result, user);
  assert.deepEqual(operation.filter, {
    passwordResetTokenHash: hashPasswordResetToken(token),
    passwordResetExpiresAt: {
      $gt: new Date(fixedNow)
    },
    isActive: true
  });
  assert.deepEqual(operation.update, {
    $set: {
      passwordHash: 'new-password-hash'
    },
    $inc: {
      authVersion: 1
    },
    $unset: {
      passwordResetTokenHash: '',
      passwordResetExpiresAt: ''
    }
  });
  assert.deepEqual(operation.options, { new: true });
});

test('password reset authVersion invalidates every older access token', () => {
  assert.equal(
    isAccessTokenCurrent(
      { authVersion: 0 },
      { authVersion: 0 }
    ),
    true
  );

  // Tokens issued before authVersion existed are treated as version zero,
  // preserving existing sessions until the user actually resets a password.
  assert.equal(
    isAccessTokenCurrent(
      {},
      { authVersion: 0 }
    ),
    true
  );

  assert.equal(
    isAccessTokenCurrent(
      { authVersion: 0 },
      { authVersion: 1 }
    ),
    false
  );

  assert.equal(
    isAccessTokenCurrent(
      { authVersion: 1 },
      { authVersion: 1 }
    ),
    true
  );
});

test('an invalid, expired or already-consumed token has one stable error', async () => {
  await assert.rejects(
    () =>
      consumePasswordReset({
        token: 'B'.repeat(43),
        newPassword: 'new-secret',
        UserModel: {
          async findOneAndUpdate() {
            return null;
          }
        },
        hashPassword: async () => 'new-password-hash'
      }),
    (error) => {
      assert.equal(error.statusCode, 400);
      assert.equal(
        error.code,
        'INVALID_PASSWORD_RESET_TOKEN'
      );
      assert.equal(
        String(error.message).includes('BBBB'),
        false
      );
      return true;
    }
  );
});

test('forgot-password validation accepts exactly one valid email field', () => {
  assert.equal(
    runMiddleware(validateForgotPassword, {
      email: 'owner@example.com'
    }),
    true
  );

  assert.throws(
    () =>
      runMiddleware(validateForgotPassword, {
        email: 'owner@example.com',
        userId: 'attacker-controlled'
      }),
    (error) =>
      error.code === 'INVALID_PASSWORD_RECOVERY_FIELDS'
  );

  assert.throws(
    () =>
      runMiddleware(validateForgotPassword, {
        email: 'not-an-email'
      }),
    (error) => error.code === 'INVALID_EMAIL'
  );
});

test('reset-password validation requires an exact token and a usable new password', () => {
  assert.equal(
    runMiddleware(validateResetPassword, {
      token: 'C'.repeat(43),
      newPassword: 'secret1'
    }),
    true
  );

  assert.throws(
    () =>
      runMiddleware(validateResetPassword, {
        token: 'C'.repeat(42),
        newPassword: 'secret1'
      }),
    (error) =>
      error.code === 'INVALID_PASSWORD_RESET_TOKEN'
  );

  assert.throws(
    () =>
      runMiddleware(validateResetPassword, {
        token: 'C'.repeat(43),
        newPassword: '12345'
      }),
    (error) => error.code === 'INVALID_PASSWORD'
  );

  assert.throws(
    () =>
      runMiddleware(validateResetPassword, {
        token: 'C'.repeat(43),
        newPassword: 'x'.repeat(73)
      }),
    (error) => error.code === 'INVALID_PASSWORD'
  );

  assert.throws(
    () =>
      runMiddleware(validateResetPassword, {
        token: 'C'.repeat(43),
        newPassword: 'secret1',
        email: 'owner@example.com'
      }),
    (error) =>
      error.code === 'INVALID_PASSWORD_RESET_FIELDS'
  );
});
