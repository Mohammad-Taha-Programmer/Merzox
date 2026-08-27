import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import mongoose from 'mongoose';

import { validateCourierLocationUpdate } from '../src/middleware/validate.js';
import { Order } from '../src/models/Order.js';
import {
  COURIER_LOCATION_CAPABILITY_TTL_MS,
  COURIER_LOCATION_ERRORS,
  courierLocationMonotonicFilter,
  courierLocationTokenFromAuthorization,
  hashCourierLocationToken,
  isCourierLocationCapabilityActive,
  issueCourierLocationCapability,
  normalizeCourierLocationPayload
} from '../src/policies/courier-location.policy.js';

function buildOrder(overrides = {}) {
  return new Order({
    user: new mongoose.Types.ObjectId(),
    business: new mongoose.Types.ObjectId(),
    businessName: 'Tracking Store',
    items: [
      {
        productId: new mongoose.Types.ObjectId(),
        name: 'Package',
        unitPrice: 20,
        quantity: 1
      }
    ],
    subtotal: 20,
    deliveryFee: 10,
    total: 30,
    deliveryAddress: 'Ramallah, Palestine',
    ...overrides
  });
}

test(
  'courier capability is 256-bit, one-time-returnable and hashed at rest',
  () => {
    const now =
      new Date('2026-08-27T04:00:00.000Z');

    const capability =
      issueCourierLocationCapability({
        now,
        randomBytes(size) {
          assert.equal(size, 32);
          return Buffer.alloc(size, 7);
        }
      });

    assert.match(
      capability.token,
      /^[A-Za-z0-9_-]{43}$/
    );

    assert.match(
      capability.tokenHash,
      /^[a-f0-9]{64}$/
    );

    assert.notEqual(
      capability.token,
      capability.tokenHash
    );

    assert.equal(
      capability.tokenHash,
      hashCourierLocationToken(
        capability.token
      )
    );

    assert.equal(
      capability.expiresAt.getTime() -
        capability.issuedAt.getTime(),
      COURIER_LOCATION_CAPABILITY_TTL_MS
    );

    const tokenPath =
      Order.schema.path(
        'courierLocationCapability.tokenHash'
      );

    assert.equal(
      tokenPath.options.select,
      false
    );

    assert.equal(
      Order.schema.path(
        'courierLocationCapability.token'
      ),
      undefined
    );
  }
);

test(
  'courier Authorization scheme is distinct from normal Bearer JWT authentication',
  () => {
    const { token } =
      issueCourierLocationCapability({
        randomBytes: (size) =>
          Buffer.alloc(size, 11)
      });

    assert.equal(
      courierLocationTokenFromAuthorization(
        `Courier ${token}`
      ),
      token
    );

    assert.equal(
      courierLocationTokenFromAuthorization(
        `Bearer ${token}`
      ),
      null
    );

    assert.equal(
      courierLocationTokenFromAuthorization(
        'Courier malformed'
      ),
      null
    );
  }
);

test(
  'capability activity fails closed for expiry and revocation',
  () => {
    const now =
      new Date('2026-08-27T04:00:00.000Z');

    const capability =
      issueCourierLocationCapability({
        now,
        randomBytes: (size) =>
          Buffer.alloc(size, 13)
      });

    assert.equal(
      isCourierLocationCapabilityActive(
        capability,
        {
          now: new Date(
            now.getTime() + 1000
          )
        }
      ),
      true
    );

    assert.equal(
      isCourierLocationCapabilityActive(
        {
          ...capability,
          revokedAt: new Date()
        },
        { now }
      ),
      false
    );

    assert.equal(
      isCourierLocationCapabilityActive(
        capability,
        {
          now: new Date(
            capability.expiresAt.getTime()
          )
        }
      ),
      false
    );
  }
);

test(
  'latest-location filter accepts only a strictly newer capturedAt sample',
  () => {
    const capturedAt =
      new Date('2026-08-27T06:00:00.000Z');

    assert.deepEqual(
      courierLocationMonotonicFilter(
        capturedAt
      ),
      {
        $or: [
          {
            courierLocation: null
          },
          {
            'courierLocation.capturedAt': {
              $exists: false
            }
          },
          {
            'courierLocation.capturedAt': {
              $lt: capturedAt
            }
          }
        ]
      }
    );

    assert.throws(
      () =>
        courierLocationMonotonicFilter(
          'not-a-date'
        ),
      /capturedAt/
    );
  }
);

test(
  'stale courier samples have a stable conflict code distinct from capability failure',
  () => {
    assert.equal(
      COURIER_LOCATION_ERRORS.staleSample,
      'COURIER_LOCATION_STALE_SAMPLE'
    );

    assert.notEqual(
      COURIER_LOCATION_ERRORS.staleSample,
      COURIER_LOCATION_ERRORS.capabilityInvalid
    );
  }
);

test(
  'location payload requires strict coordinates and a fresh capture timestamp',
  () => {
    const now =
      new Date('2026-08-27T04:15:00.000Z');

    const good =
      normalizeCourierLocationPayload(
        {
          latitude: 31.9038,
          longitude: 35.2034,
          accuracy: 8.5,
          capturedAt:
            '2026-08-27T04:14:30.000Z'
        },
        { now }
      );

    assert.equal(good.ok, true);
    assert.equal(
      good.value.latitude,
      31.9038
    );
    assert.equal(
      good.value.longitude,
      35.2034
    );
    assert.equal(
      good.value.accuracy,
      8.5
    );
    assert.equal(
      good.value.capturedAt.toISOString(),
      '2026-08-27T04:14:30.000Z'
    );

    assert.equal(
      normalizeCourierLocationPayload(
        {
          latitude: 91,
          longitude: 35,
          capturedAt:
            '2026-08-27T04:14:30.000Z'
        },
        { now }
      ).code,
      COURIER_LOCATION_ERRORS.invalidLatitude
    );

    assert.equal(
      normalizeCourierLocationPayload(
        {
          latitude: 31,
          longitude: 181,
          capturedAt:
            '2026-08-27T04:14:30.000Z'
        },
        { now }
      ).code,
      COURIER_LOCATION_ERRORS.invalidLongitude
    );

    assert.equal(
      normalizeCourierLocationPayload(
        {
          latitude: 31,
          longitude: 35,
          capturedAt:
            '2026-08-27T03:00:00.000Z'
        },
        { now }
      ).code,
      COURIER_LOCATION_ERRORS.invalidCapturedAt
    );

    assert.equal(
      normalizeCourierLocationPayload(
        {
          latitude: 31,
          longitude: 35,
          capturedAt:
            '2026-08-27T04:14:30.000Z',
          unexpected: true
        },
        { now }
      ).code,
      COURIER_LOCATION_ERRORS.invalidFields
    );
  }
);

test(
  'validation middleware writes only a normalized location payload',
  () => {
    const req = {
      body: {
        latitude: 31.9,
        longitude: 35.2,
        accuracy: null,
        capturedAt:
          new Date().toISOString()
      }
    };

    let nextCalled = false;

    validateCourierLocationUpdate(
      req,
      {},
      () => {
        nextCalled = true;
      }
    );

    assert.equal(nextCalled, true);

    assert.deepEqual(
      Object.keys(
        req.courierLocationPayload
      ).sort(),
      [
        'accuracy',
        'capturedAt',
        'latitude',
        'longitude'
      ]
    );

    assert.equal(
      req.courierLocationPayload
        .capturedAt instanceof Date,
      true
    );
  }
);

test(
  'Order tracking exposes latest location only during active delivery capability',
  () => {
    const now = new Date();

    const future =
      new Date(
        now.getTime() +
          60 * 60 * 1000
      );

    const capturedAt =
      new Date(
        now.getTime() - 1000
      );

    const receivedAt =
      new Date(
        now.getTime() - 500
      );

    const order =
      buildOrder({
        status: 'outForDelivery',
        courier: {
          name: 'Courier One',
          phone: '+970599000000',
          assignedAt: now
        },
        courierLocationCapability: {
          tokenHash: 'a'.repeat(64),
          issuedAt: now,
          expiresAt: future,
          revokedAt: null
        },
        courierLocation: {
          latitude: 31.9038,
          longitude: 35.2034,
          accuracy: 7,
          capturedAt,
          receivedAt
        }
      });

    assert.equal(
      order.validateSync(),
      undefined
    );

    const client =
      order.toClientJSON();

    assert.deepEqual(
      client.tracking.courierLocation,
      {
        latitude: 31.9038,
        longitude: 35.2034,
        accuracy: 7,
        capturedAt,
        receivedAt,
        capabilityExpiresAt: future
      }
    );

    const serialized =
      JSON.stringify(client);

    assert.equal(
      serialized.includes(
        'courierLocationCapability'
      ),
      false
    );

    assert.equal(
      serialized.includes(
        'a'.repeat(64)
      ),
      false
    );

    order.status = 'delivered';

    assert.equal(
      order.trackingJSON()
        .courierLocation,
      null
    );

    order.status = 'outForDelivery';
    order.courierLocationCapability.revokedAt =
      new Date();

    assert.equal(
      order.trackingJSON()
        .courierLocation,
      null
    );
  }
);

test(
  'courier write atomically fences stale samples before replacing latest location',
  async () => {
    const source =
      await readFile(
        new URL(
          '../src/controllers/courier-location.controller.js',
          import.meta.url
        ),
        'utf8'
      );

    assert.match(
      source,
      /courierLocationMonotonicFilter\(\s*location\.capturedAt\s*\)/
    );

    assert.match(
      source,
      /COURIER_LOCATION_ERRORS\.staleSample/
    );

    const updateIndex =
      source.indexOf(
        'await Order.findOneAndUpdate'
      );

    const staleDiagnosisIndex =
      source.indexOf(
        'await Order.exists'
      );

    assert.ok(
      updateIndex >= 0 &&
      staleDiagnosisIndex > updateIndex
    );
  }
);

test(
  'capability write route is before the normal JWT order router guard',
  async () => {
    const source =
      await readFile(
        new URL(
          '../src/routes/order.routes.js',
          import.meta.url
        ),
        'utf8'
      );

    const capabilityRoute =
      source.indexOf(
        "'/:id/courier-location'"
      );

    const authGuard =
      source.indexOf(
        'router.use(requireAuth);'
      );

    assert.notEqual(
      capabilityRoute,
      -1
    );

    assert.notEqual(
      authGuard,
      -1
    );

    assert.ok(
      capabilityRoute < authGuard
    );
  }
);

test(
  'customer cancellation clears courier location authority and latest snapshot',
  async () => {
    const source =
      await readFile(
        new URL(
          '../src/controllers/order.controller.js',
          import.meta.url
        ),
        'utf8'
      );

    const start =
      source.indexOf(
        'export const cancelMyOrder'
      );

    assert.notEqual(
      start,
      -1
    );

    const cancellation =
      source.slice(start);

    assert.match(
      cancellation,
      /'courierLocationCapability\.tokenHash': ''/
    );

    assert.match(
      cancellation,
      /'courierLocationCapability\.revokedAt':\s*cancelledAt/
    );

    assert.match(
      cancellation,
      /courierLocation: null/
    );

    assert.match(
      cancellation,
      /status: 'cancelled'/
    );
  }
);

test(
  'merchant has explicit capability revocation and reassignment rotates the secret',
  async () => {
    const controller =
      await readFile(
        new URL(
          '../src/controllers/merchant.controller.js',
          import.meta.url
        ),
        'utf8'
      );

    const routes =
      await readFile(
        new URL(
          '../src/routes/business.routes.js',
          import.meta.url
        ),
        'utf8'
      );

    assert.match(
      controller,
      /issueCourierLocationCapability/
    );

    assert.match(
      controller,
      /tokenHash: capability\.tokenHash/
    );

    assert.match(
      controller,
      /token: capability\.token/
    );

    assert.match(
      controller,
      /revokeMyBusinessOrderCourierLocation/
    );

    assert.match(
      routes,
      /courier-location-capability/
    );
  }
);
