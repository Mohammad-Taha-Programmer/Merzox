import assert from 'node:assert/strict';
import test from 'node:test';

import {
  FREE_BUSINESS_PUBLIC_ID_COUNT,
  FREE_BUSINESS_PUBLIC_ID_MAX,
  FREE_BUSINESS_PUBLIC_ID_MIN,
  RESERVED_BUSINESS_PUBLIC_IDS,
  createBusinessWithUniquePublicId,
  generateBusinessPublicId,
  isPublicIdDuplicateKeyError,
  isReservedBusinessPublicId
} from '../src/services/business-public-id.service.js';

test('generator covers the complete free namespace without reserved IDs', () => {
  assert.equal(FREE_BUSINESS_PUBLIC_ID_COUNT, 89982);

  const generated = new Set();

  for (
    let offset = 0;
    offset < FREE_BUSINESS_PUBLIC_ID_COUNT;
    offset += 1
  ) {
    const publicId = generateBusinessPublicId({
      randomInt: (minimum, maximum) => {
        assert.equal(minimum, 0);
        assert.equal(
          maximum,
          FREE_BUSINESS_PUBLIC_ID_COUNT
        );

        return offset;
      }
    });

    const numericId = Number(publicId);

    assert.match(publicId, /^\d{5}$/);

    assert.ok(
      numericId >= FREE_BUSINESS_PUBLIC_ID_MIN
    );

    assert.ok(
      numericId <= FREE_BUSINESS_PUBLIC_ID_MAX
    );

    assert.equal(
      isReservedBusinessPublicId(publicId),
      false
    );

    generated.add(publicId);
  }

  assert.equal(
    generated.size,
    FREE_BUSINESS_PUBLIC_ID_COUNT
  );

  assert.equal(generated.has('10001'), true);
  assert.equal(generated.has('99998'), true);

  for (const reservedId of RESERVED_BUSINESS_PUBLIC_IDS) {
    assert.equal(
      generated.has(String(reservedId)),
      false
    );
  }
});

test('reserved identifiers include premium and out-of-free-range values', () => {
  for (const reservedId of [
    10000,
    20000,
    90000,
    11111,
    55555,
    99999,
    100000
  ]) {
    assert.equal(
      isReservedBusinessPublicId(reservedId),
      true
    );
  }

  assert.equal(
    isReservedBusinessPublicId(54321),
    false
  );
});

test('allocator checks the database and skips an existing public ID', async () => {
  const offsets = [0, 1];
  const checkedIds = [];
  const createdValues = [];

  const BusinessModel = {
    async exists({ publicId }) {
      checkedIds.push(publicId);
      return publicId === '10001';
    },

    async create(values) {
      createdValues.push(values);
      return values;
    }
  };

  const business = await createBusinessWithUniquePublicId(
    {
      owner: 'owner-1',
      name: 'Test business'
    },
    {
      BusinessModel,
      randomInt: () => offsets.shift()
    }
  );

  assert.deepEqual(checkedIds, ['10001', '10002']);
  assert.equal(createdValues.length, 1);
  assert.equal(business.publicId, '10002');
  assert.equal(business.owner, 'owner-1');
});

test('allocator retries a concurrent publicId unique-index collision', async () => {
  const offsets = [0, 1];
  const createdIds = [];

  const BusinessModel = {
    async exists() {
      return false;
    },

    async create(values) {
      createdIds.push(values.publicId);

      if (createdIds.length === 1) {
        const collision = new Error(
          'duplicate key on publicId_1'
        );

        collision.code = 11000;
        collision.keyPattern = { publicId: 1 };

        throw collision;
      }

      return values;
    }
  };

  const business = await createBusinessWithUniquePublicId(
    {
      owner: 'owner-2',
      name: 'Concurrent business'
    },
    {
      BusinessModel,
      randomInt: () => offsets.shift()
    }
  );

  assert.deepEqual(createdIds, ['10001', '10002']);
  assert.equal(business.publicId, '10002');
});

test('allocator does not hide duplicate errors for another unique field', async () => {
  const ownerCollision = new Error(
    'duplicate key on unique_business_owner'
  );

  ownerCollision.code = 11000;
  ownerCollision.keyPattern = { owner: 1 };

  const BusinessModel = {
    async exists() {
      return false;
    },

    async create() {
      throw ownerCollision;
    }
  };

  await assert.rejects(
    () =>
      createBusinessWithUniquePublicId(
        {
          owner: 'owner-3',
          name: 'Duplicate owner'
        },
        {
          BusinessModel,
          randomInt: () => 0
        }
      ),
    (error) => {
      assert.equal(error, ownerCollision);
      return true;
    }
  );

  assert.equal(
    isPublicIdDuplicateKeyError(ownerCollision),
    false
  );
});

test('allocator fails closed after its bounded attempt limit', async () => {
  let existenceChecks = 0;

  const BusinessModel = {
    async exists() {
      existenceChecks += 1;
      return true;
    },

    async create() {
      assert.fail(
        'create must not run for an existing public ID'
      );
    }
  };

  await assert.rejects(
    () =>
      createBusinessWithUniquePublicId(
        {
          owner: 'owner-4',
          name: 'Unavailable ID'
        },
        {
          BusinessModel,
          randomInt: () => 0,
          maxAttempts: 3
        }
      ),
    (error) => {
      assert.equal(
        error.code,
        'BUSINESS_PUBLIC_ID_UNAVAILABLE'
      );

      return true;
    }
  );

  assert.equal(existenceChecks, 3);
});
