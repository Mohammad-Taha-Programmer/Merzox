import express from 'express';
import morgan from 'morgan';

import { env } from './config/env.js';
import { errorHandler, notFoundHandler } from './middleware/errorHandler.js';
import { applySecurityMiddleware } from './middleware/security.js';
import authRoutes from './routes/auth.routes.js';
import businessRoutes from './routes/business.routes.js';
import contentRoutes from './routes/content.routes.js';
import favoriteRoutes from './routes/favorite.routes.js';
import orderRoutes from './routes/order.routes.js';
import searchRoutes from './routes/search.routes.js';
import userRoutes from './routes/user.routes.js';

const app = express();

applySecurityMiddleware(app);

if (env.nodeEnv !== 'test') {
  app.use(morgan(env.nodeEnv === 'production' ? 'combined' : 'dev'));
}

app.use(express.json({ limit: '32kb' }));

app.get('/health', (_req, res) => {
  res.json({ success: true, data: { status: 'ok', service: 'merzox-api' } });
});

app.use('/api/v1/auth', authRoutes);
app.use('/api/v1/businesses', businessRoutes);
app.use('/api/v1/content', contentRoutes);
app.use('/api/v1/favorites', favoriteRoutes);
app.use('/api/v1/orders', orderRoutes);
app.use('/api/v1/search', searchRoutes);
app.use('/api/v1/users', userRoutes);

app.use(notFoundHandler);
app.use(errorHandler);

export default app;
