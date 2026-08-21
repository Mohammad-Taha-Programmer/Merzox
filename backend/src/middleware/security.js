import compression from 'compression';
import cors from 'cors';
import mongoSanitize from 'express-mongo-sanitize';
import rateLimit from 'express-rate-limit';
import helmet from 'helmet';
import hpp from 'hpp';

import { env } from '../config/env.js';

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

export function applySecurityMiddleware(app) {
  app.disable('x-powered-by');
  app.use(helmet());
  app.use(compression());
  app.use(
    cors({
      origin(origin, callback) {
        callback(null, isOriginAllowed(origin));
      },
      credentials: true
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
