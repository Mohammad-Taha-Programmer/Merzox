import express from 'express';

import { env } from './config/env.js';
import { currentReadiness } from './runtime/readiness.js';
import { applyProxyTrust } from './runtime/proxy-trust.js';
import { errorHandler, notFoundHandler } from './middleware/errorHandler.js';
import { requestContextMiddleware } from './middleware/request-context.js';
import { applySecurityMiddleware } from './middleware/security.js';
import authRoutes from './routes/auth.routes.js';
import businessRoutes from './routes/business.routes.js';
import contentRoutes from './routes/content.routes.js';
import favoriteRoutes from './routes/favorite.routes.js';
import messageRoutes from './routes/message.routes.js';
import notificationRoutes from './routes/notification.routes.js';
import pushRegistrationRoutes from './routes/push-registration.routes.js';
import orderRoutes from './routes/order.routes.js';
import searchRoutes from './routes/search.routes.js';
import userRoutes from './routes/user.routes.js';

const app = express();

applyProxyTrust(
  app,
  env.trustedProxyRanges
);

app.use(
  requestContextMiddleware
);

applySecurityMiddleware(app);

app.use(express.json({ limit: '32kb' }));

app.get('/health', (_req, res) => {
  res.json({ success: true, data: { status: 'ok', service: 'merzox-api' } });
});

app.get('/ready', (_req, res) => {
  const readiness = currentReadiness();

  res
    .status(readiness.ready ? 200 : 503)
    .json({
      success: readiness.ready,
      data: {
        status: readiness.status,
        service: readiness.service
      }
    });
});

app.use('/api/v1/auth', authRoutes);
app.use('/api/v1/businesses', businessRoutes);
app.use('/api/v1/content', contentRoutes);
app.use('/api/v1/conversations', messageRoutes);
app.use('/api/v1/favorites', favoriteRoutes);
app.use('/api/v1/notifications', notificationRoutes);
app.use('/api/v1/push', pushRegistrationRoutes);
app.use('/api/v1/orders', orderRoutes);
app.use('/api/v1/search', searchRoutes);
app.use('/api/v1/users', userRoutes);

app.use(notFoundHandler);
app.use(errorHandler);

export default app;
