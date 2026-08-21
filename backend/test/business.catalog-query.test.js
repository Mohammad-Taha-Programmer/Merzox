import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildBusinessFilter,
  buildNearbyBusinessFilter,
  businessSort,
  nearbyBusinessSort,
  nearbyParams,
  paginationParams
} from '../src/controllers/business.controller.js';

test('business catalog uses deterministic newest and rating ordering', () => {
  assert.deepEqual(businessSort({ sort: 'newest' }), {
    subscribedAt: -1,
    _id: -1
  });
  assert.deepEqual(businessSort({ sort: 'rating' }), {
    ratingAverage: -1,
    ratingCount: -1,
    subscribedAt: -1,
    _id: -1
  });
});

test('business catalog rejects unsupported sorting and discount filters', () => {
  assert.throws(
    () => businessSort({ sort: 'popular' }),
    (error) => error.code === 'INVALID_BUSINESS_SORT' && error.statusCode === 400
  );
  assert.throws(
    () => buildBusinessFilter({ discounted: 'yes' }),
    (error) =>
      error.code === 'INVALID_DISCOUNTED_FILTER' && error.statusCode === 400
  );
});

test('discounted catalog queries retain active-business filtering', () => {
  assert.deepEqual(buildBusinessFilter({ discounted: 'true' }), {
    isActive: true,
    discountLabel: { $exists: true, $type: 'string', $ne: '' }
  });
  assert.deepEqual(buildBusinessFilter({ discounted: 'false' }), {
    isActive: true
  });
});

test('catalog pagination is bounded and computes the server skip', () => {
  assert.deepEqual(paginationParams({ page: '3', limit: '20' }), {
    page: 3,
    limit: 20,
    skip: 40
  });
  assert.deepEqual(paginationParams({ page: '0', limit: '500' }), {
    page: 1,
    limit: 100,
    skip: 0
  });
});

test('nearby catalog accepts valid coordinates and keeps active filtering', () => {
  assert.deepEqual(nearbyBusinessSort(), {
    distanceMeters: 1,
    subscribedAt: -1,
    _id: -1
  });
  assert.deepEqual(
    nearbyParams({ lat: '31.9038', lng: '35.2034', radiusMeters: '25000' }),
    { latitude: 31.9038, longitude: 35.2034, radiusMeters: 25000 }
  );
  assert.equal(nearbyParams({ lat: '95', lng: '35.2' }), null);
  assert.deepEqual(buildNearbyBusinessFilter({ search: 'shop' }), {
    isActive: true,
    $or: [
      { name: { $regex: 'shop', $options: 'i' } },
      { category: { $regex: 'shop', $options: 'i' } },
      { 'products.name': { $regex: 'shop', $options: 'i' } }
    ]
  });
});
