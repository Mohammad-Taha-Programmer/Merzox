import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createBusinessProductReview,
  createBusinessReview,
  getBusinessProductReviewEligibility,
  getBusinessReviewEligibility
} from '../src/controllers/business.controller.js';
import { requireAuth } from '../src/middleware/auth.js';
import businessRouter from '../src/routes/business.routes.js';

function routeHandlers(method, path) {
  const layer = businessRouter.stack.find(
    (candidate) =>
      candidate.route?.path === path &&
      candidate.route.methods?.[method] === true
  );

  assert.ok(layer, `${method.toUpperCase()} ${path} must exist`);

  return layer.route.stack.map((entry) => entry.handle);
}

test('business eligibility GET is authenticated guidance only', () => {
  assert.deepEqual(
    routeHandlers('get', '/:id/review-eligibility'),
    [
      requireAuth,
      getBusinessReviewEligibility
    ]
  );
});

test('product eligibility GET is authenticated guidance only', () => {
  assert.deepEqual(
    routeHandlers('get', '/:id/products/:productId/review-eligibility'),
    [
      requireAuth,
      getBusinessProductReviewEligibility
    ]
  );
});

test('a business review needs a session, and nothing more at the door', () => {
  // The customer-only guard is gone on purpose. A merchant buying from
  // another merchant is that shop's customer, and the one review nobody may
  // write - their own shop's - needs to know whose shop it is, which only the
  // handler does.
  assert.deepEqual(
    routeHandlers('post', '/:id/reviews'),
    [requireAuth, createBusinessReview]
  );
});

test('a product review is guarded the same way', () => {
  assert.deepEqual(
    routeHandlers('post', '/:id/products/:productId/reviews'),
    [requireAuth, createBusinessProductReview]
  );
});
