import assert from 'node:assert/strict';
import test from 'node:test';

import { getMyRecommendations } from '../src/controllers/recommendation.controller.js';
import { requireAuth } from '../src/middleware/auth.js';
import userRouter from '../src/routes/user.routes.js';

function routeHandlers(method, path) {
  const layer = userRouter.stack.find(
    (candidate) =>
      candidate.route?.path === path &&
      candidate.route.methods?.[method] === true
  );

  assert.ok(
    layer,
    `${method.toUpperCase()} ${path} must exist`
  );

  return layer.route.stack.map(
    (entry) => entry.handle
  );
}

test('recommendation endpoint is authenticated and uses the exact controller', () => {
  assert.deepEqual(
    routeHandlers(
      'get',
      '/me/recommendations'
    ),
    [
      requireAuth,
      getMyRecommendations
    ]
  );
});
