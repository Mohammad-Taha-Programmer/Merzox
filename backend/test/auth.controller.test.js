import assert from 'node:assert/strict';
import test from 'node:test';

/**
 * The auth handlers, driven directly.
 *
 * These seven handlers are the security boundary of the whole product, and
 * until now nothing exercised them: the only coverage was the authorization
 * matrix, which needs MongoDB and is skipped everywhere it is not provisioned.
 *
 * No database and no mail server are involved here. SMTP is blanked and the
 * public base URL is pinned before the config module is read - so
 * `sendVerificationEmail` resolves to its not-configured branch instead of
 * posting a real message, and the links these tests read back do not depend on
 * whatever a developer put in `.env`. The two model statics the handlers touch
 * are replaced per test and restored afterwards.
 */
process.env.PUBLIC_BASE_URL = 'https://merzox.test';
process.env.SMTP_HOST = '';
process.env.SMTP_USER = '';
process.env.SMTP_PASS = '';
process.env.SMTP_FROM = '';

const { User } = await import('../src/models/User.js');
const { verifyAccessToken } = await import('../src/utils/jwt.js');
const {
  login,
  logout,
  me,
  signup,
  verifyEmail
} = await import('../src/controllers/auth.controller.js');

/**
 * Runs one handler and reports whichever of the two endings happened: a
 * response, or the error `asyncHandler` forwarded to `next`.
 */
function invoke(handler, req = {}) {
  return new Promise((resolve) => {
    const captured = { status: 200, body: null, error: null };
    const res = {
      status(code) {
        captured.status = code;
        return res;
      },
      json(payload) {
        captured.body = payload;
        resolve(captured);
        return res;
      }
    };

    handler(
      { body: {}, query: {}, params: {}, ...req },
      res,
      (error) => {
        captured.error = error;
        resolve(captured);
      }
    );
  });
}

/** A Mongoose query stand-in: awaitable, and chainable through `.select`. */
function queryResult(value) {
  return {
    select: () => Promise.resolve(value),
    then: (resolve, reject) => Promise.resolve(value).then(resolve, reject)
  };
}

/**
 * Replaces the two model entry points the handlers use, and hands back the
 * saved documents plus a restore function.
 */
function stubUser({ found = null } = {}) {
  const originalFindOne = User.findOne;
  const originalSave = User.prototype.save;
  const state = { saved: [], filters: [] };

  User.findOne = (filter) => {
    state.filters.push(filter);
    return queryResult(typeof found === 'function' ? found(filter) : found);
  };
  User.prototype.save = async function save() {
    state.saved.push(this);
    return this;
  };

  state.restore = () => {
    User.findOne = originalFindOne;
    User.prototype.save = originalSave;
  };

  return state;
}

async function makeUser(overrides = {}) {
  const user = new User({
    name: 'ياسمين خالد',
    email: 'yasmine@example.com',
    emailVerified: true,
    isActive: true,
    userType: 'normal',
    ...overrides
  });

  await user.setPassword('correct-horse');

  return user;
}

// ---------------------------------------------------------------------------
// signup
// ---------------------------------------------------------------------------

test('signup refuses an identifier that already belongs to an account', async () => {
  const stub = stubUser({ found: await makeUser() });

  try {
    const result = await invoke(signup, {
      body: {
        name: 'ياسمين',
        email: 'yasmine@example.com',
        password: 'correct-horse'
      }
    });

    assert.equal(result.error?.code, 'ACCOUNT_EXISTS');
    assert.equal(result.error?.statusCode, 409);
    assert.equal(stub.saved.length, 0);
  } finally {
    stub.restore();
  }
});

test('an email signup stores nothing until the address is proven', async () => {
  const stub = stubUser();

  try {
    const result = await invoke(signup, {
      body: {
        name: 'ياسمين خالد',
        email: 'Yasmine@Example.com',
        password: 'correct-horse',
        gender: 'female'
      }
    });

    assert.equal(result.error, null);
    assert.equal(result.status, 202);
    assert.equal(result.body.data.requiresEmailVerification, true);
    // No mailer is configured here, and the handler reports that honestly
    // rather than claiming a delivery it did not make.
    assert.equal(result.body.data.emailSent, false);
    // The account does not exist yet. This is the whole point of the branch.
    assert.equal(stub.saved.length, 0);
  } finally {
    stub.restore();
  }
});

test('the pending signup travels encrypted, not as readable claims', async () => {
  const stub = stubUser();

  try {
    const result = await invoke(signup, {
      body: {
        name: 'ياسمين خالد',
        email: 'yasmine@example.com',
        password: 'correct-horse'
      }
    });

    const link = result.body.data.verificationLink;
    assert.ok(link, 'a non-production signup returns the link it would send');

    const token = new URL(link).searchParams.get('token');
    const decoded = Buffer.from(token, 'base64url').toString('latin1');

    // The token carries a password hash. Neither it nor the address may be
    // legible to whoever forwards the mail.
    assert.equal(token.includes('yasmine'), false);
    assert.equal(decoded.includes('yasmine'), false);
    assert.equal(decoded.includes('$2'), false);
  } finally {
    stub.restore();
  }
});

test('a phone signup creates the account immediately', async () => {
  const stub = stubUser();

  try {
    const result = await invoke(signup, {
      body: {
        name: 'سامر',
        phone: '0592029316',
        password: 'correct-horse'
      }
    });

    assert.equal(result.error, null);
    assert.equal(result.status, 201);
    assert.equal(result.body.data.requiresEmailVerification, false);
    assert.equal(stub.saved.length, 1);

    const saved = stub.saved[0];
    // There is no address to verify, so the account is usable at once.
    assert.equal(saved.emailVerified, true);
    assert.equal(saved.phones[0].isPrimary, true);
    assert.ok(saved.passwordHash, 'the password is stored hashed, not raw');
    assert.notEqual(saved.passwordHash, 'correct-horse');
  } finally {
    stub.restore();
  }
});

// ---------------------------------------------------------------------------
// verifyEmail
// ---------------------------------------------------------------------------

test('a verified link creates the account the signup withheld', async () => {
  const first = stubUser();
  let link;

  try {
    const result = await invoke(signup, {
      body: {
        name: 'ياسمين خالد',
        email: 'yasmine@example.com',
        password: 'correct-horse',
        address: 'رام الله'
      }
    });
    link = result.body.data.verificationLink;
  } finally {
    first.restore();
  }

  const token = new URL(link).searchParams.get('token');
  const second = stubUser();

  try {
    const result = await invoke(verifyEmail, { query: { token } });

    assert.equal(result.error, null);
    assert.equal(second.saved.length, 1);

    const saved = second.saved[0];
    assert.equal(saved.email, 'yasmine@example.com');
    assert.equal(saved.emailVerified, true);
    assert.equal(saved.emails[0].verified, true);
    assert.equal(saved.address, 'رام الله');
    // The hash made at signup is carried across, so the password the user
    // chose then is the password that works now.
    assert.ok(saved.passwordHash.startsWith('$2'));
  } finally {
    second.restore();
  }
});

test('a missing, tampered or truncated token is refused', async () => {
  const stub = stubUser();

  try {
    for (const query of [
      {},
      { token: '' },
      { token: 'not-a-token' },
      { token: 'AAAA.BBBB.CCCC' }
    ]) {
      const result = await invoke(verifyEmail, { query });

      assert.equal(
        result.error?.code,
        'INVALID_VERIFICATION_TOKEN',
        `token ${JSON.stringify(query)} must not verify anything`
      );
    }

    assert.equal(stub.saved.length, 0);
  } finally {
    stub.restore();
  }
});

test('a link that arrives after its day is refused', async () => {
  const first = stubUser();
  let token;

  try {
    const result = await invoke(signup, {
      body: {
        name: 'ياسمين',
        email: 'late@example.com',
        password: 'correct-horse'
      }
    });
    token = new URL(result.body.data.verificationLink).searchParams.get('token');
  } finally {
    first.restore();
  }

  const second = stubUser();
  const realNow = Date.now;
  Date.now = () => realNow() + 1000 * 60 * 60 * 25;

  try {
    const result = await invoke(verifyEmail, { query: { token } });

    assert.equal(result.error?.code, 'INVALID_VERIFICATION_TOKEN');
    assert.equal(second.saved.length, 0);
  } finally {
    Date.now = realNow;
    second.restore();
  }
});

test('a link cannot be replayed once the account exists', async () => {
  const first = stubUser();
  let token;

  try {
    const result = await invoke(signup, {
      body: {
        name: 'ياسمين',
        email: 'twice@example.com',
        password: 'correct-horse'
      }
    });
    token = new URL(result.body.data.verificationLink).searchParams.get('token');
  } finally {
    first.restore();
  }

  const second = stubUser({ found: await makeUser({ email: 'twice@example.com' }) });

  try {
    const result = await invoke(verifyEmail, { query: { token } });

    assert.equal(result.error?.code, 'ACCOUNT_EXISTS');
    assert.equal(second.saved.length, 0);
  } finally {
    second.restore();
  }
});

// ---------------------------------------------------------------------------
// login
// ---------------------------------------------------------------------------

test('an unknown account and a wrong password are the same refusal', async () => {
  const absent = stubUser({ found: null });
  let unknown;

  try {
    unknown = await invoke(login, {
      body: { identifier: 'nobody@example.com', password: 'correct-horse' }
    });
  } finally {
    absent.restore();
  }

  const present = stubUser({ found: await makeUser() });
  let wrong;

  try {
    wrong = await invoke(login, {
      body: { identifier: 'yasmine@example.com', password: 'wrong-password' }
    });
  } finally {
    present.restore();
  }

  // Anything that separated these two would let a stranger enumerate accounts.
  assert.equal(unknown.error?.code, 'INVALID_CREDENTIALS');
  assert.equal(wrong.error?.code, 'INVALID_CREDENTIALS');
  assert.equal(unknown.error.statusCode, wrong.error.statusCode);
  assert.equal(unknown.error.message, wrong.error.message);
});

test('login answers with a token that names the account and its version', async () => {
  const user = await makeUser();
  const stub = stubUser({ found: user });

  try {
    const result = await invoke(login, {
      body: { identifier: 'yasmine@example.com', password: 'correct-horse' }
    });

    assert.equal(result.error, null);

    const payload = verifyAccessToken(result.body.data.token);
    assert.equal(payload.sub, user._id.toString());
    assert.equal(payload.userType, 'normal');
    // The version is what makes a token revocable at all.
    assert.equal(payload.authVersion, 0);

    // The account travels through `toSafeJSON`, which owns what is public.
    assert.equal(
      Object.prototype.hasOwnProperty.call(result.body.data.user, 'passwordHash'),
      false
    );
  } finally {
    stub.restore();
  }
});

test('an unverified address cannot be used to log in', async () => {
  const stub = stubUser({
    found: await makeUser({ emailVerified: false })
  });

  try {
    const result = await invoke(login, {
      body: { identifier: 'yasmine@example.com', password: 'correct-horse' }
    });

    assert.equal(result.error?.code, 'EMAIL_NOT_VERIFIED');
    assert.equal(result.error?.statusCode, 403);
  } finally {
    stub.restore();
  }
});

test('an unverified address does not block the phone it was signed up with', async () => {
  const stub = stubUser({
    found: await makeUser({
      email: 'yasmine@example.com',
      emailVerified: false,
      phone: '0592029316'
    })
  });

  try {
    const result = await invoke(login, {
      body: { identifier: '0592029316', password: 'correct-horse' }
    });

    // The gate is about the address being proven, not about the account.
    assert.equal(result.error, null);
    assert.ok(result.body.data.token);
  } finally {
    stub.restore();
  }
});

test('a disabled account is refused after the password checks out', async () => {
  const stub = stubUser({ found: await makeUser({ isActive: false }) });

  try {
    const result = await invoke(login, {
      body: { identifier: 'yasmine@example.com', password: 'correct-horse' }
    });

    assert.equal(result.error?.code, 'ACCOUNT_DISABLED');
    assert.equal(result.error?.statusCode, 403);
  } finally {
    stub.restore();
  }
});

test('login looks the account up by either identifier, normalized', async () => {
  const stub = stubUser({ found: await makeUser() });

  try {
    await invoke(login, {
      body: { identifier: '  Yasmine@Example.COM ', password: 'correct-horse' }
    });

    const [filter] = stub.filters;
    assert.deepEqual(filter.$or[0], { email: 'yasmine@example.com' });
    assert.equal(typeof filter.$or[1].phone, 'string');
  } finally {
    stub.restore();
  }
});

// ---------------------------------------------------------------------------
// me and logout
// ---------------------------------------------------------------------------

test('me answers with the public projection of the caller', async () => {
  const user = await makeUser();
  const result = await invoke(me, { user });

  assert.equal(result.error, null);
  assert.equal(result.body.data.user.email, 'yasmine@example.com');
  assert.equal(
    Object.prototype.hasOwnProperty.call(result.body.data.user, 'passwordHash'),
    false
  );
});

test('logout is a courtesy: it revokes nothing', async () => {
  const user = await makeUser();
  const token = (
    await (async () => {
      const stub = stubUser({ found: user });
      try {
        return await invoke(login, {
          body: { identifier: 'yasmine@example.com', password: 'correct-horse' }
        });
      } finally {
        stub.restore();
      }
    })()
  ).body.data.token;

  const result = await invoke(logout, { user });

  assert.equal(result.error, null);
  assert.equal(result.body.success, true);
  // Stated rather than assumed: the token issued above still verifies after
  // logging out. Killing it would mean bumping `authVersion`, which only a
  // password reset does today.
  assert.equal(verifyAccessToken(token).sub, user._id.toString());
});
