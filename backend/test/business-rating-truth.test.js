import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

import { Business } from '../src/models/Business.js';
import { BusinessReview } from '../src/models/BusinessReview.js';

const seedSource = readFileSync(
  new URL('../src/scripts/seed.js', import.meta.url),
  'utf8',
);

test('new businesses start with a zero rating aggregate', () => {
  const business = new Business();

  assert.equal(business.ratingAverage, 0);
  assert.equal(business.ratingCount, 0);
});

test('one user has at most one review document per business', () => {
  const compoundIndex = BusinessReview.schema
    .indexes()
    .find(([fields, options]) => {
      return (
        fields.business === 1 &&
        fields.user === 1 &&
        options.unique === true
      );
    });

  assert.ok(compoundIndex);
});

test('seeded businesses and products do not receive synthetic ratings', () => {
  assert.doesNotMatch(
    seedSource,
    /ratingAverage:\s*3\.8/,
  );

  assert.doesNotMatch(
    seedSource,
    /ratingCount:\s*12\s*\+\s*index/,
  );

  assert.doesNotMatch(
    seedSource,
    /ratingCount:\s*5\s*\+\s*productIndex/,
  );

  const zeroAverages =
    seedSource.match(/ratingAverage:\s*0/g) ?? [];

  const zeroCounts =
    seedSource.match(/ratingCount:\s*0/g) ?? [];

  assert.ok(zeroAverages.length >= 2);
  assert.ok(zeroCounts.length >= 2);
});
