import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildBusinessFilter,
  buildNearbyBusinessFilter,
  businessSort,
  classificationParam,
  discountedParam,
  nearbyBusinessSort,
  nearbyParams,
  paginationParams,
  searchParam
} from '../src/controllers/business.controller.js';

function throwsCode(fn, code) {
  assert.throws(
    fn,
    (error) =>
      error.code === code &&
      error.statusCode === 400
  );
}

test('business catalog uses deterministic newest and rating ordering', () => {
  assert.deepEqual(businessSort({}), {
    subscribedAt: -1,
    _id: -1
  });

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

test('business sorting rejects invalid, blank and repeated values', () => {
  for (const value of ['popular', '', ' newest ']) {
    throwsCode(
      () => businessSort({ sort: value }),
      'INVALID_BUSINESS_SORT'
    );
  }

  throwsCode(
    () => businessSort({ sort: ['newest', 'rating'] }),
    'INVALID_BUSINESS_SORT'
  );
});

test('discounted filter accepts only exact boolean representations', () => {
  assert.equal(discountedParam({}), false);
  assert.equal(discountedParam({ discounted: 'true' }), true);
  assert.equal(discountedParam({ discounted: 'false' }), false);
  assert.equal(discountedParam({ discounted: true }), true);
  assert.equal(discountedParam({ discounted: false }), false);

  for (const value of ['yes', '', ' true ', '1']) {
    throwsCode(
      () => discountedParam({ discounted: value }),
      'INVALID_DISCOUNTED_FILTER'
    );
  }

  throwsCode(
    () => discountedParam({ discounted: ['true', 'false'] }),
    'INVALID_DISCOUNTED_FILTER'
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

test('business pagination preserves endpoint defaults and bounds', () => {
  assert.deepEqual(paginationParams({}), {
    page: 1,
    limit: 100,
    skip: 0
  });

  assert.deepEqual(
    paginationParams({}, { limitFallback: 20 }),
    {
      page: 1,
      limit: 20,
      skip: 0
    }
  );

  assert.deepEqual(
    paginationParams({ page: '3', limit: '20' }),
    {
      page: 3,
      limit: 20,
      skip: 40
    }
  );

  assert.deepEqual(
    paginationParams({ page: '2', limit: '500' }),
    {
      page: 2,
      limit: 100,
      skip: 100
    }
  );
});

test('business pagination rejects malformed page values', () => {
  const invalid = [
    '0',
    '-1',
    '+1',
    '1.5',
    '1e3',
    '1abc',
    'abc1',
    '',
    '   ',
    'NaN',
    'Infinity',
    '9007199254740992',
    ' 2 '
  ];

  for (const value of invalid) {
    throwsCode(
      () => paginationParams({ page: value }),
      'INVALID_PAGE'
    );
  }

  throwsCode(
    () => paginationParams({ page: ['1', '2'] }),
    'INVALID_PAGE'
  );
});

test('business pagination rejects malformed limit values', () => {
  const invalid = [
    '0',
    '-1',
    '+1',
    '1.5',
    '1e3',
    '12x',
    '',
    '   ',
    'NaN',
    'Infinity',
    '9007199254740992',
    ' 20 '
  ];

  for (const value of invalid) {
    throwsCode(
      () => paginationParams({ limit: value }),
      'INVALID_LIMIT'
    );
  }

  throwsCode(
    () => paginationParams({ limit: ['10', '20'] }),
    'INVALID_LIMIT'
  );
});

test('nearby catalog accepts valid short and long coordinate aliases', () => {
  assert.deepEqual(
    nearbyParams({
      lat: '31.9038',
      lng: '35.2034',
      radiusMeters: '25000'
    }),
    {
      latitude: 31.9038,
      longitude: 35.2034,
      radiusMeters: 25000
    }
  );

  assert.deepEqual(
    nearbyParams({
      latitude: '31.9038',
      longitude: '35.2034'
    }),
    {
      latitude: 31.9038,
      longitude: 35.2034,
      radiusMeters: 10000
    }
  );

  assert.equal(nearbyParams({}), null);
});

test('nearby catalog accepts coordinate boundaries and clamps radius bounds', () => {
  assert.deepEqual(
    nearbyParams({ lat: '-90', lng: '-180', radiusMeters: '1' }),
    {
      latitude: -90,
      longitude: -180,
      radiusMeters: 100
    }
  );

  assert.deepEqual(
    nearbyParams({ lat: '90', lng: '180', radiusMeters: '99999' }),
    {
      latitude: 90,
      longitude: 180,
      radiusMeters: 50000
    }
  );
});

test('nearby catalog rejects incomplete and ambiguous coordinate input', () => {
  for (const query of [
    { lat: '31.9' },
    { lng: '35.2' },
    { latitude: '31.9' },
    { longitude: '35.2' },
    { radiusMeters: '1000' }
  ]) {
    throwsCode(
      () => nearbyParams(query),
      'INCOMPLETE_NEARBY_COORDINATES'
    );
  }

  throwsCode(
    () =>
      nearbyParams({
        lat: '31.9',
        latitude: '31.9',
        lng: '35.2'
      }),
    'AMBIGUOUS_NEARBY_COORDINATES'
  );

  throwsCode(
    () =>
      nearbyParams({
        lat: '31.9',
        lng: '35.2',
        longitude: '35.2'
      }),
    'AMBIGUOUS_NEARBY_COORDINATES'
  );
});

test('nearby catalog rejects malformed latitude values', () => {
  const invalid = [
    '',
    '   ',
    'NaN',
    'Infinity',
    '1abc',
    '1e2',
    '+31.9',
    '31.9 ',
    '91',
    '-91'
  ];

  for (const value of invalid) {
    throwsCode(
      () => nearbyParams({ lat: value, lng: '35.2' }),
      'INVALID_LATITUDE'
    );
  }

  throwsCode(
    () => nearbyParams({ lat: ['31.9', '32'], lng: '35.2' }),
    'INVALID_LATITUDE'
  );
});

test('nearby catalog rejects malformed longitude values', () => {
  const invalid = [
    '',
    '   ',
    'NaN',
    'Infinity',
    '35abc',
    '1e2',
    '+35.2',
    '35.2 ',
    '181',
    '-181'
  ];

  for (const value of invalid) {
    throwsCode(
      () => nearbyParams({ lat: '31.9', lng: value }),
      'INVALID_LONGITUDE'
    );
  }

  throwsCode(
    () => nearbyParams({ lat: '31.9', lng: ['35.2', '35.3'] }),
    'INVALID_LONGITUDE'
  );
});

test('nearby catalog rejects malformed radius values', () => {
  const invalid = [
    '0',
    '-1',
    '+1',
    '1.5',
    '1e3',
    '500abc',
    '',
    '   ',
    'NaN',
    'Infinity'
  ];

  for (const value of invalid) {
    throwsCode(
      () =>
        nearbyParams({
          lat: '31.9',
          lng: '35.2',
          radiusMeters: value
        }),
      'INVALID_RADIUS_METERS'
    );
  }

  throwsCode(
    () =>
      nearbyParams({
        lat: '31.9',
        lng: '35.2',
        radiusMeters: ['1000', '2000']
      }),
    'INVALID_RADIUS_METERS'
  );
});

test('nearby ordering remains deterministic', () => {
  assert.deepEqual(nearbyBusinessSort(), {
    distanceMeters: 1,
    subscribedAt: -1,
    _id: -1
  });
});

test('product classification defaults only when absent and rejects explicit invalid values', () => {
  assert.equal(classificationParam({}), 'new');
  assert.equal(
    classificationParam({ classification: 'new' }),
    'new'
  );
  assert.equal(
    classificationParam({ classification: 'bestSelling' }),
    'bestSelling'
  );
  assert.equal(
    classificationParam({ classification: 'offers' }),
    'offers'
  );

  for (const value of ['unknown', '', ' new ']) {
    throwsCode(
      () => classificationParam({ classification: value }),
      'INVALID_PRODUCT_CLASSIFICATION'
    );
  }

  throwsCode(
    () =>
      classificationParam({
        classification: ['new', 'offers']
      }),
    'INVALID_PRODUCT_CLASSIFICATION'
  );
});

test('search preserves trim and length rules but rejects repeated values', () => {
  assert.equal(searchParam({}), '');
  assert.equal(searchParam({ search: '  phone  ' }), 'phone');
  assert.equal(
    searchParam({ search: 'x'.repeat(100) }),
    'x'.repeat(80)
  );

  throwsCode(
    () => searchParam({ search: ['phone', 'tablet'] }),
    'INVALID_BUSINESS_SEARCH'
  );
});

test('nearby search escapes regular-expression syntax', () => {
  const filter = buildNearbyBusinessFilter({
    search: 'shop.*(x)'
  });

  assert.equal(filter.isActive, true);
  assert.equal(
    filter.$or[0].name.$regex,
    'shop\\.\\*\\(x\\)'
  );
  assert.equal(filter.$or[0].name.$options, 'i');
});

test('normal and nearby catalog filters always retain active-business filtering', () => {
  assert.deepEqual(buildBusinessFilter({ search: '' }), {
    isActive: true
  });

  const nearby = buildNearbyBusinessFilter({
    search: 'shop'
  });

  assert.equal(nearby.isActive, true);
  assert.deepEqual(nearby.$or, [
    { name: { $regex: 'shop', $options: 'i' } },
    { category: { $regex: 'shop', $options: 'i' } },
    { 'products.name': { $regex: 'shop', $options: 'i' } }
  ]);
});
