import compression from 'compression';
import cors from 'cors';
import mongoSanitize from 'express-mongo-sanitize';
import rateLimit from 'express-rate-limit';
import helmet from 'helmet';
import hpp from 'hpp';

import { env } from '../config/env.js';
import { AppError } from '../utils/AppError.js';

export const PASSWORD_RECOVERY_RATE_LIMIT_WINDOW_MS = 15 * 60 * 1000;
export const FORGOT_PASSWORD_RATE_LIMIT_MAX = 5;
export const RESET_PASSWORD_RATE_LIMIT_MAX = 20;

/**
 * The credential endpoints get their own budgets.
 *
 * Password recovery has been limited since it was written; the front door was
 * not, and stood behind the global allowance alone - hundreds of attempts per
 * window, shared with browsing. Guessing a password is the cheapest attack
 * this API offers, so it is the one that most needs its own ceiling.
 */
export const CREDENTIAL_RATE_LIMIT_WINDOW_MS = 15 * 60 * 1000;

/**
 * Counted per address, and only when the attempt fails - a household behind
 * one address can sign in all day, while twenty wrong guesses in a quarter of
 * an hour stops.
 *
 * Configurable through `LOGIN_RATE_LIMIT_MAX` the way the global allowance
 * already is, because the integration harness drives the real HTTP API and
 * would otherwise throttle itself.
 */
export const LOGIN_RATE_LIMIT_MAX = env.loginRateLimitMax;

/** Creating accounts is the abuse, so every attempt counts here. */
export const SIGNUP_RATE_LIMIT_MAX = env.signupRateLimitMax;

function isOriginAllowed(origin) {
  if (!origin) {
    return true;
  }

  return env.corsOrigins.some((allowed) => {
    if (allowed.endsWith('*')) {
      return origin.startsWith(allowed.slice(0, -1));
    }

    return origin === allowed;
  });
}

function passwordRecoveryLimiter({ max, code }) {
  return rateLimit({
    windowMs: PASSWORD_RECOVERY_RATE_LIMIT_WINDOW_MS,
    max,
    standardHeaders: true,
    legacyHeaders: false,
    handler(_req, _res, next) {
      next(
        new AppError(
          'Too many password recovery attempts. Try again later.',
          429,
          code
        )
      );
    }
  });
}

function credentialLimiter({ max, code, message, skipSuccessfulRequests = false }) {
  return rateLimit({
    windowMs: CREDENTIAL_RATE_LIMIT_WINDOW_MS,
    max,
    skipSuccessfulRequests,
    standardHeaders: true,
    legacyHeaders: false,
    handler(_req, _res, next) {
      next(new AppError(message, 429, code));
    }
  });
}

export const loginLimiter = credentialLimiter({
  max: LOGIN_RATE_LIMIT_MAX,
  code: 'LOGIN_RATE_LIMITED',
  message: 'Too many sign-in attempts. Try again later.',
  // A successful sign-in must not spend the budget, or a shared address would
  // lock out the people using it correctly.
  skipSuccessfulRequests: true
});

export const signupLimiter = credentialLimiter({
  max: SIGNUP_RATE_LIMIT_MAX,
  code: 'SIGNUP_RATE_LIMITED',
  message: 'Too many sign-up attempts. Try again later.'
});

export const forgotPasswordLimiter = passwordRecoveryLimiter({
  max: FORGOT_PASSWORD_RATE_LIMIT_MAX,
  code: 'PASSWORD_RECOVERY_RATE_LIMITED'
});

export const resetPasswordLimiter = passwordRecoveryLimiter({
  max: RESET_PASSWORD_RATE_LIMIT_MAX,
  code: 'PASSWORD_RESET_RATE_LIMITED'
});

export function applySecurityMiddleware(app) {
  app.disable('x-powered-by');
  app.use(helmet());
  app.use(compression());
  app.use(
    cors({
      origin(origin, callback) {
        callback(null, isOriginAllowed(origin));
      },
      credentials: true,
      exposedHeaders: [
        'X-Request-ID'
      ]
    })
  );
  app.use(
    rateLimit({
      windowMs: env.rateLimitWindowMs,
      max: env.rateLimitMax,
      standardHeaders: true,
      legacyHeaders: false
    })
  );
  app.use(mongoSanitize());
  app.use(hpp());
}
