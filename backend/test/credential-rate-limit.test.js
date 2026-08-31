import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

import {
  CREDENTIAL_RATE_LIMIT_WINDOW_MS,
  LOGIN_RATE_LIMIT_MAX,
  SIGNUP_RATE_LIMIT_MAX,
  loginLimiter,
  signupLimiter
} from '../src/middleware/security.js';

/**
 * The front door has its own budget.
 *
 * Password recovery has been limited since it was written - five attempts a
 * quarter hour - while sign-in stood behind the global allowance alone, three
 * hundred requests a window shared with browsing the catalogue. Guessing a
 * password is the cheapest attack this API offers, so it now has the tightest
 * ceiling of the three.
 */

const here = path.dirname(fileURLToPath(import.meta.url));

/**
 * Drives one limiter as Express would, and reports what came back.
 *
 * `express-rate-limit` writes headers and reads the status code off the
 * response, so the double has to answer both. `finish` is emitted because that
 * is when a skipped successful request is given back to the budget.
 */
async function attempt(limiter, { ip = '203.0.113.9', statusCode = 401 } = {}) {
  const listeners = [];
  let refusal = null;

  const req = {
    ip,
    ips: [],
    method: 'POST',
    headers: {},
    app: { get: () => false },
    socket: { remoteAddress: ip }
  };

  const res = {
    statusCode,
    headers: {},
    setHeader(name, value) {
      this.headers[name] = value;
    },
    getHeader(name) {
      return this.headers[name];
    },
    removeHeader(name) {
      delete this.headers[name];
    },
    on(event, listener) {
      if (event === 'finish') listeners.push(listener);
      return this;
    },
    once(event, listener) {
      return this.on(event, listener);
    },
    end() {
      for (const listener of listeners) listener();
    }
  };

  await new Promise((resolve) => {
    limiter(req, res, (error) => {
      refusal = error ?? null;
      resolve();
    });
  });

  // Express ends the response after the handler; that is when a successful
  // attempt is refunded.
  res.end();

  return refusal;
}

test('the credential window matches the recovery window', () => {
  assert.equal(CREDENTIAL_RATE_LIMIT_WINDOW_MS, 15 * 60 * 1000);
});

test('sign-in stops after twenty failures from one address', async () => {
  const ip = '203.0.113.10';

  for (let attemptNumber = 1; attemptNumber <= LOGIN_RATE_LIMIT_MAX; attemptNumber += 1) {
    assert.equal(
      await attempt(loginLimiter, { ip }),
      null,
      `attempt ${attemptNumber} is within the budget`
    );
  }

  const refused = await attempt(loginLimiter, { ip });

  assert.equal(refused?.code, 'LOGIN_RATE_LIMITED');
  assert.equal(refused?.statusCode, 429);
});

test('a successful sign-in is refunded, so a household is never locked out', async () => {
  const ip = '203.0.113.11';

  // Far past the ceiling, but every one of them worked.
  for (let attemptNumber = 0; attemptNumber < LOGIN_RATE_LIMIT_MAX * 3; attemptNumber += 1) {
    assert.equal(await attempt(loginLimiter, { ip, statusCode: 200 }), null);
  }

  assert.equal(await attempt(loginLimiter, { ip, statusCode: 200 }), null);
});

test('sign-up counts every attempt, successful or not', async () => {
  const ip = '203.0.113.12';

  for (let attemptNumber = 1; attemptNumber <= SIGNUP_RATE_LIMIT_MAX; attemptNumber += 1) {
    assert.equal(await attempt(signupLimiter, { ip, statusCode: 202 }), null);
  }

  const refused = await attempt(signupLimiter, { ip, statusCode: 202 });

  assert.equal(refused?.code, 'SIGNUP_RATE_LIMITED');
  assert.equal(refused?.statusCode, 429);
});

test('one address exhausting its budget does not spend another one', async () => {
  const exhausted = '203.0.113.13';

  for (let attemptNumber = 0; attemptNumber <= LOGIN_RATE_LIMIT_MAX; attemptNumber += 1) {
    await attempt(loginLimiter, { ip: exhausted });
  }

  assert.equal((await attempt(loginLimiter, { ip: exhausted }))?.code, 'LOGIN_RATE_LIMITED');
  assert.equal(await attempt(loginLimiter, { ip: '203.0.113.14' }), null);
});

test('both credential routes carry their limiter', () => {
  const routes = readFileSync(
    path.join(here, '..', 'src', 'routes', 'auth.routes.js'),
    'utf8'
  );

  // Ahead of validation on purpose: a flood of malformed bodies is still a
  // flood, and it should spend the budget rather than skip it.
  assert.match(routes, /router\.post\(\s*'\/login',\s*loginLimiter,/);
  assert.match(routes, /router\.post\(\s*'\/signup',\s*signupLimiter,/);
});

test('the credential ceiling is the tightest of the three', async () => {
  const { FORGOT_PASSWORD_RATE_LIMIT_MAX, RESET_PASSWORD_RATE_LIMIT_MAX } =
    await import('../src/middleware/security.js');

  // Recovery sends mail, so it is stricter still; both are far below the
  // global allowance the front door used to rely on.
  assert.ok(FORGOT_PASSWORD_RATE_LIMIT_MAX < SIGNUP_RATE_LIMIT_MAX);
  assert.ok(SIGNUP_RATE_LIMIT_MAX < LOGIN_RATE_LIMIT_MAX);
  assert.ok(LOGIN_RATE_LIMIT_MAX <= RESET_PASSWORD_RATE_LIMIT_MAX);
});
