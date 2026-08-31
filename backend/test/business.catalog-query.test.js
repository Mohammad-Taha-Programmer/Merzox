import assert from 'node:assert/strict';
import { once } from 'node:events';
import test from 'node:test';

import app from '../src/app.js';
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

test('HTTP boundary rejects supported repeated business query parameters after HPP normalization', async (t) => {
  const server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');

  t.after(
    () =>
      new Promise((resolve, reject) => {
        server.close((error) => {
          if (error) {
            reject(error);
            return;
          }

          resolve();
        });
      })
  );

  const address = server.address();
  assert.ok(address && typeof address === 'object');

  const baseUrl = `http://127.0.0.1:${address.port}`;

  const cases = [
    ['/api/v1/businesses?page=1&page=2', 'INVALID_PAGE'],
    [
      '/api/v1/businesses?search=phone&search=tablet',
      'INVALID_BUSINESS_SEARCH'
    ],
    [
      '/api/v1/businesses?lat=31.9&lat=32.0&lng=35.2',
      'INVALID_LATITUDE'
    ],
    [
      '/api/v1/businesses/demo/products?classification=new&classification=offers',
      'INVALID_PRODUCT_CLASSIFICATION'
    ],
    [
      '/api/v1/businesses/demo/reviews?page=1&page=2',
      'INVALID_PAGE'
    ],
    [
      '/api/v1/businesses/demo/products/demo/reviews?limit=10&limit=20',
      'INVALID_LIMIT'
    ]
  ];

  for (const [path, expectedCode] of cases) {
    const response = await fetch(`${baseUrl}${path}`);
    const payload = await response.json();

    assert.equal(
      response.status,
      400,
      `${path} should be rejected before any database query`
    );

    assert.equal(
      payload.error?.code,
      expectedCode,
      `${path} should expose the stable validation code`
    );
  }
});


// ---------------------------------------------------------------------------
// Searching a catalogue that has no text index
// ---------------------------------------------------------------------------

test('a search falls back when there is no text index to use', async () => {
  const {
    buildBusinessFilter,
    buildBusinessSearchFallbackFilter,
    withTextIndexFallback,
    TEXT_INDEX_MISSING
  } = await import('../src/controllers/business.controller.js');

  const attempts = [];
  const result = await withTextIndexFallback({ search: 'الياسمين' }, (filter) => {
    attempts.push(filter);

    if (attempts.length === 1) {
      const error = new Error('text index required for $text query');
      error.code = TEXT_INDEX_MISSING;
      throw error;
    }

    return 'answered';
  });

  assert.equal(result, 'answered');
  assert.equal(attempts.length, 2);
  // The first attempt is the fast path.
  assert.deepEqual(attempts[0], buildBusinessFilter({ search: 'الياسمين' }));
  // The second asks the same question without needing an index.
  assert.deepEqual(
    attempts[1],
    buildBusinessSearchFallbackFilter({ search: 'الياسمين' })
  );
  assert.equal(attempts[1].$text, undefined);
  assert.equal(attempts[1].$or.length, 3);
});

test('the fallback needle is escaped, not executed', async () => {
  const { buildBusinessSearchFallbackFilter } = await import(
    '../src/controllers/business.controller.js'
  );

  const filter = buildBusinessSearchFallbackFilter({ search: 'a.*b' });
  const [byName] = filter.$or;

  assert.equal(byName.name.$regex, String.raw`a\.\*b`);
  assert.equal(new RegExp(byName.name.$regex).test('a.*b'), true);
  assert.equal(new RegExp(byName.name.$regex).test('axxb'), false);
});

test('a search with no needle never reaches the fallback', async () => {
  const { withTextIndexFallback, TEXT_INDEX_MISSING } = await import(
    '../src/controllers/business.controller.js'
  );

  let attempts = 0;

  await assert.rejects(
    withTextIndexFallback({}, () => {
      attempts += 1;
      const error = new Error('some other missing index');
      error.code = TEXT_INDEX_MISSING;
      throw error;
    }),
    /some other missing index/
  );

  // Retrying an unrelated missing index would hide a real fault.
  assert.equal(attempts, 1);
});

test('any other database failure is passed on untouched', async () => {
  const { withTextIndexFallback } = await import(
    '../src/controllers/business.controller.js'
  );

  let attempts = 0;

  await assert.rejects(
    withTextIndexFallback({ search: 'x' }, () => {
      attempts += 1;
      const error = new Error('connection lost');
      error.code = 89;
      throw error;
    }),
    /connection lost/
  );

  assert.equal(attempts, 1);
});
