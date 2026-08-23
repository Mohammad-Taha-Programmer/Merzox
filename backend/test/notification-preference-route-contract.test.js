import assert from 'node:assert/strict';
import test from 'node:test';

import {
  getMyNotificationPreferences,
  updateMyNotificationPreferences
} from '../src/controllers/user.controller.js';
import { requireAuth } from '../src/middleware/auth.js';
import userRouter from '../src/routes/user.routes.js';

function routeHandlers(method, path) {
  const layer = userRouter.stack.find(
    (candidate) =>
      candidate.route?.path === path &&
      candidate.route.methods?.[method] === true
  );

  assert.ok(layer, `${method.toUpperCase()} ${path} must exist`);

  return layer.route.stack.map((entry) => entry.handle);
}

test('notification preference GET requires authentication', () => {
  assert.deepEqual(
    routeHandlers('get', '/me/notification-preferences'),
    [
      requireAuth,
      getMyNotificationPreferences
    ]
  );
});

test('notification preference PATCH requires authentication and exact controller', () => {
  assert.deepEqual(
    routeHandlers('patch', '/me/notification-preferences'),
    [
      requireAuth,
      updateMyNotificationPreferences
    ]
  );
});
