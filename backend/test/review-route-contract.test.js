import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createBusinessProductReview,
  createBusinessReview,
  getBusinessProductReviewEligibility,
  getBusinessReviewEligibility
} from '../src/controllers/business.controller.js';
import {
  requireAuth,
  requireCustomerUser
} from '../src/middleware/auth.js';
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

test('business review POST requires both auth and customer role', () => {
  assert.deepEqual(
    routeHandlers('post', '/:id/reviews'),
    [
      requireAuth,
      requireCustomerUser,
      createBusinessReview
    ]
  );
});

test('product review POST requires both auth and customer role', () => {
  assert.deepEqual(
    routeHandlers('post', '/:id/products/:productId/reviews'),
    [
      requireAuth,
      requireCustomerUser,
      createBusinessProductReview
    ]
  );
});
