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
