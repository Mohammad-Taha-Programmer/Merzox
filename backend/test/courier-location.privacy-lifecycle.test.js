import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

import {
  courierLocationLimits,
  isCourierLocationSnapshotVisible
} from '../src/policies/courier-location.policy.js';

import {
  publishOrderTrackingChanged,
  registerRealtimeEmitter
} from '../src/realtime/realtime.publisher.js';

function validSnapshot({
  now,
  capturedAt = now,
  expiresAt =
    new Date(
      now.getTime() +
      60 * 60 * 1000
    )
} = {}) {
  return {
    status: 'outForDelivery',
    capability: {
      tokenHash: 'a'.repeat(64),
      expiresAt,
      revokedAt: null
    },
    location: {
      latitude: 31.9038,
      longitude: 35.2034,
      accuracy: 7,
      capturedAt,
      receivedAt: now
    }
  };
}

function exportedFunctionSource(
  source,
  name
) {
  const marker =
    `export const ${name}`;

  const start =
    source.indexOf(marker);

  assert.ok(
    start >= 0,
    `${name} must exist`
  );

  const next =
    source.indexOf(
      '\nexport const ',
      start + marker.length
    );

  return source.slice(
    start,
    next < 0
      ? source.length
      : next
  );
}

function assertPersistThenPublish(
  block,
  reason
) {
  const write =
    block.indexOf(
      'await Order.findOneAndUpdate'
    );

  const publish =
    block.indexOf(
      'publishOrderTrackingChanged({'
    );

  assert.ok(write >= 0);
  assert.ok(publish > write);

  assert.match(
    block,
    new RegExp(
      `reason:\\s*'${reason}'`
    )
  );
}

test(
  'customer courier snapshot expires fifteen minutes after capturedAt',
  () => {
    const capturedAt =
      new Date(
        '2026-08-27T06:00:00.000Z'
      );

    const atBoundary =
      new Date(
        capturedAt.getTime() +
        courierLocationLimits.maximumPastAgeMs
      );

    assert.equal(
      isCourierLocationSnapshotVisible(
        validSnapshot({
          now: atBoundary,
          capturedAt
        }),
        { now: atBoundary }
      ),
      true
    );

    const stale =
      new Date(
        atBoundary.getTime() + 1
      );

    assert.equal(
      isCourierLocationSnapshotVisible(
        validSnapshot({
          now: stale,
          capturedAt
        }),
        { now: stale }
      ),
      false
    );
  }
);

test(
  'customer courier snapshot fails closed for lifecycle and malformed location state',
  () => {
    const now =
      new Date(
        '2026-08-27T06:00:00.000Z'
      );

    const base =
      validSnapshot({ now });

    assert.equal(
      isCourierLocationSnapshotVisible(
        {
          ...base,
          status: 'delivered'
        },
        { now }
      ),
      false
    );

    assert.equal(
      isCourierLocationSnapshotVisible(
        {
          ...base,
          capability: {
            ...base.capability,
            revokedAt: now
          }
        },
        { now }
      ),
      false
    );

    assert.equal(
      isCourierLocationSnapshotVisible(
        {
          ...base,
          capability: {
            ...base.capability,
            expiresAt: now
          }
        },
        { now }
      ),
      false
    );

    // Capability metadata alone is not authority.
    // Missing or malformed token hashes must fail closed.
    assert.equal(
      isCourierLocationSnapshotVisible(
        {
          ...base,
          capability: {
            expiresAt: base.capability.expiresAt,
            revokedAt: null
          }
        },
        { now }
      ),
      false,
      'snapshot must be hidden when token hash is absent'
    );

    assert.equal(
      isCourierLocationSnapshotVisible(
        {
          ...base,
          capability: {
            ...base.capability,
            tokenHash: 'not-a-valid-hash'
          }
        },
        { now }
      ),
      false,
      'snapshot must be hidden when token hash is malformed'
    );

    assert.equal(
      isCourierLocationSnapshotVisible(
        {
          ...base,
          location: {
            ...base.location,
            latitude: 95
          }
        },
        { now }
      ),
      false
    );
  }
);

test(
  'order tracking publisher accepts only approved lifecycle reasons and never requires coordinates',
  () => {
    const emissions = [];

    const unregister =
      registerRealtimeEmitter(
        (
          userId,
          event,
          payload
        ) => {
          emissions.push({
            userId,
            event,
            payload
          });
        }
      );

    try {
      for (const reason of [
        'courier-location-updated',
        'courier-location-cleared',
        'order-status-changed'
      ]) {
        assert.equal(
          publishOrderTrackingChanged({
            recipientIds: [
              'customer-1'
            ],
            orderId: 'order-1',
            reason
          }),
          true
        );
      }

      assert.equal(
        publishOrderTrackingChanged({
          recipientIds: [
            'customer-1'
          ],
          orderId: 'order-1',
          reason:
            'coordinates-updated'
        }),
        false
      );

      assert.equal(
        emissions.length,
        3
      );

      for (const emission of emissions) {
        assert.deepEqual(
          Object.keys(
            emission.payload
          ).sort(),
          [
            'orderId',
            'reason'
          ]
        );
      }
    } finally {
      unregister();
    }
  }
);

test(
  'merchant reassignment revoke and status transitions publish only after durable order mutation',
  () => {
    const source =
      fs.readFileSync(
        new URL(
          '../src/controllers/merchant.controller.js',
          import.meta.url
        ),
        'utf8'
      );

    const status =
      exportedFunctionSource(
        source,
        'updateMyBusinessOrderStatus'
      );

    const assign =
      exportedFunctionSource(
        source,
        'updateMyBusinessOrderCourier'
      );

    const revoke =
      exportedFunctionSource(
        source,
        'revokeMyBusinessOrderCourierLocation'
      );

    assertPersistThenPublish(
      status,
      'order-status-changed'
    );

    assertPersistThenPublish(
      assign,
      'courier-location-cleared'
    );

    assertPersistThenPublish(
      revoke,
      'courier-location-cleared'
    );

    for (const block of [
      status,
      assign,
      revoke
    ]) {
      const publish =
        block.indexOf(
          'publishOrderTrackingChanged({'
        );

      const response =
        block.indexOf(
          'res.json({',
          publish
        );

      assert.ok(
        response > publish
      );

      const publishBlock =
        block.slice(
          publish,
          response
        );

      assert.doesNotMatch(
        publishBlock,
        /\b(latitude|longitude|accuracy|capturedAt|receivedAt)\b/
      );
    }
  }
);

test(
  'customer cancellation publishes status invalidation after cancellation is durable',
  () => {
    const source =
      fs.readFileSync(
        new URL(
          '../src/controllers/order.controller.js',
          import.meta.url
        ),
        'utf8'
      );

    const cancel =
      exportedFunctionSource(
        source,
        'cancelMyOrder'
      );

    assertPersistThenPublish(
      cancel,
      'order-status-changed'
    );

    assert.match(
      cancel,
      /recipientIds:\s*\[order\.user\]/
    );
  }
);
