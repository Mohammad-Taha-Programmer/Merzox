import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

import {
  validatePushRegistrationDelete,
  validatePushRegistrationUpsert
} from '../src/middleware/push-registration.validate.js';
import { PushRegistration } from '../src/models/PushRegistration.js';
import {
  normalizePushTarget,
  PUSH_PLATFORMS,
  PUSH_TARGET_KINDS
} from '../src/policies/push-registration.policy.js';
import { createPushRegistrationService } from '../src/services/push-registration.service.js';

function validationError(fn, body) {
  let nextCalled = false;

  const req = { body };

  try {
    fn(
      req,
      {},
      () => {
        nextCalled = true;
      }
    );
  } catch (error) {
    return {
      error,
      req,
      nextCalled
    };
  }

  return {
    error: null,
    req,
    nextCalled
  };
}

test(
  'push target kinds remain future-compatible token and fid',
  () => {
    assert.deepEqual(
      PUSH_TARGET_KINDS,
      ['token', 'fid']
    );
  }
);

test(
  'push registration is intentionally limited to mobile platforms',
  () => {
    assert.deepEqual(
      PUSH_PLATFORMS,
      ['android', 'ios']
    );
  }
);

test(
  'push targets are treated as opaque identifiers and normalized',
  () => {
    assert.equal(
      normalizePushTarget(
        '  token-value-1234567890  '
      ),
      'token-value-1234567890'
    );

    assert.equal(
      normalizePushTarget(
        'fid_value-1234567890'
      ),
      'fid_value-1234567890'
    );
  }
);

test(
  'invalid or whitespace-bearing push targets are refused',
  () => {
    assert.equal(
      normalizePushTarget(null),
      null
    );

    assert.equal(
      normalizePushTarget('short'),
      null
    );

    assert.equal(
      normalizePushTarget(
        'target with whitespace 12345'
      ),
      null
    );
  }
);

test(
  'registration validator accepts only exact server contract fields',
  () => {
    const valid = validationError(
      validatePushRegistrationUpsert,
      {
        targetKind: 'token',
        target:
          '  registration-token-1234567890  ',
        platform: 'android'
      }
    );

    assert.equal(valid.error, null);
    assert.equal(valid.nextCalled, true);
    assert.equal(
      valid.req.body.target,
      'registration-token-1234567890'
    );

    const injected = validationError(
      validatePushRegistrationUpsert,
      {
        targetKind: 'token',
        target:
          'registration-token-1234567890',
        platform: 'android',
        userId:
          'attacker-controlled-user'
      }
    );

    assert.equal(
      injected.error?.code,
      'INVALID_PUSH_REGISTRATION_FIELDS'
    );

    assert.equal(
      injected.nextCalled,
      false
    );
  }
);

test(
  'registration validator rejects unknown kind and platform',
  () => {
    const kind = validationError(
      validatePushRegistrationUpsert,
      {
        targetKind: 'apns',
        target:
          'registration-token-1234567890',
        platform: 'ios'
      }
    );

    assert.equal(
      kind.error?.code,
      'INVALID_PUSH_TARGET_KIND'
    );

    const platform = validationError(
      validatePushRegistrationUpsert,
      {
        targetKind: 'token',
        target:
          'registration-token-1234567890',
        platform: 'windows'
      }
    );

    assert.equal(
      platform.error?.code,
      'INVALID_PUSH_PLATFORM'
    );
  }
);

test(
  'unregister validator accepts only target identity and no user id',
  () => {
    const valid = validationError(
      validatePushRegistrationDelete,
      {
        targetKind: 'fid',
        target:
          'firebase-installation-id-123456'
      }
    );

    assert.equal(valid.error, null);
    assert.equal(valid.nextCalled, true);

    const injected = validationError(
      validatePushRegistrationDelete,
      {
        targetKind: 'fid',
        target:
          'firebase-installation-id-123456',
        userId: 'other-user'
      }
    );

    assert.equal(
      injected.error?.code,
      'INVALID_PUSH_REGISTRATION_FIELDS'
    );
  }
);

test(
  'push target is globally unique and hidden from normal projections',
  () => {
    assert.equal(
      PushRegistration.schema.path('target')
        .options.select,
      false
    );

    const indexes =
      PushRegistration.schema.indexes();

    const uniqueTarget = indexes.find(
      ([keys, options]) =>
        keys.targetKind === 1 &&
        keys.target === 1 &&
        options.unique === true
    );

    assert.ok(uniqueTarget);

    assert.equal(
      uniqueTarget[1].name,
      'unique_push_target'
    );
  }
);

test(
  'push registration records carry owner and freshness indexes',
  () => {
    const indexes =
      PushRegistration.schema.indexes();

    assert.ok(
      indexes.some(
        ([keys]) =>
          keys.user === 1 &&
          keys.updatedAt === -1 &&
          keys._id === -1
      )
    );

    assert.ok(
      indexes.some(
        ([keys]) =>
          keys.lastSeenAt === 1
      )
    );
  }
);

test(
  'register derives persistence ownership from the supplied authenticated identity',
  async () => {
    const calls = [];
    const now =
      new Date('2026-08-26T08:30:00.000Z');

    const service =
      createPushRegistrationService({
        registrationModel: {
          async findOneAndUpdate(
            filter,
            update,
            options
          ) {
            calls.push({
              filter,
              update,
              options
            });

            return { _id: 'registration-1' };
          }
        },
        now: () => now
      });

    const result = await service.register({
      userId: 'server-user-1',
      targetKind: 'token',
      target:
        'registration-token-1234567890',
      platform: 'android'
    });

    assert.deepEqual(
      calls[0].filter,
      {
        targetKind: 'token',
        target:
          'registration-token-1234567890'
      }
    );

    assert.equal(
      calls[0].update.$set.user,
      'server-user-1'
    );

    assert.equal(
      calls[0].update.$set.lastSeenAt,
      now
    );

    assert.equal(
      calls[0].options.upsert,
      true
    );

    assert.equal(result.registered, true);
    assert.equal(
      result.lastSeenAt,
      now
    );

    // The opaque target is intentionally not returned.
    assert.equal(
      Object.hasOwn(result, 'target'),
      false
    );
  }
);

test(
  'registering one target for another account transfers ownership',
  async () => {
    let stored = null;

    const service =
      createPushRegistrationService({
        registrationModel: {
          async findOneAndUpdate(
            _filter,
            update
          ) {
            stored = {
              ...(stored ?? {}),
              ...update.$set
            };

            return stored;
          }
        }
      });

    const target =
      'shared-device-token-1234567890';

    await service.register({
      userId: 'first-user',
      targetKind: 'token',
      target,
      platform: 'android'
    });

    assert.equal(
      stored.user,
      'first-user'
    );

    await service.register({
      userId: 'second-user',
      targetKind: 'token',
      target,
      platform: 'android'
    });

    assert.equal(
      stored.user,
      'second-user'
    );

    assert.equal(
      stored.target,
      target
    );
  }
);

test(
  'a concurrent unique-target race retries without a second upsert',
  async () => {
    const calls = [];

    const service =
      createPushRegistrationService({
        registrationModel: {
          async findOneAndUpdate(
            filter,
            update,
            options
          ) {
            calls.push({
              filter,
              update,
              options
            });

            if (calls.length === 1) {
              const error =
                new Error('duplicate');

              error.code = 11000;
              throw error;
            }

            return { _id: 'winner' };
          }
        }
      });

    const result = await service.register({
      userId: 'user-1',
      targetKind: 'fid',
      target:
        'firebase-installation-id-123456',
      platform: 'ios'
    });

    assert.equal(result.registered, true);
    assert.equal(calls.length, 2);
    assert.equal(
      calls[0].options.upsert,
      true
    );
    assert.equal(
      calls[1].options.upsert,
      false
    );
  }
);

test(
  'non-duplicate persistence failures are never hidden',
  async () => {
    const expected =
      new Error('database unavailable');

    const service =
      createPushRegistrationService({
        registrationModel: {
          async findOneAndUpdate() {
            throw expected;
          }
        }
      });

    await assert.rejects(
      () =>
        service.register({
          userId: 'user-1',
          targetKind: 'token',
          target:
            'registration-token-1234567890',
          platform: 'android'
        }),
      (error) => error === expected
    );
  }
);

test(
  'unregister is scoped to authenticated owner and exact target',
  async () => {
    let observedFilter;

    const service =
      createPushRegistrationService({
        registrationModel: {
          async deleteOne(filter) {
            observedFilter = filter;

            return {
              deletedCount: 1
            };
          }
        }
      });

    const result =
      await service.unregister({
        userId: 'authenticated-user',
        targetKind: 'token',
        target:
          'registration-token-1234567890'
      });

    assert.deepEqual(
      observedFilter,
      {
        user: 'authenticated-user',
        targetKind: 'token',
        target:
          'registration-token-1234567890'
      }
    );

    assert.deepEqual(
      result,
      { unregistered: true }
    );
  }
);

test(
  'unregister is idempotent when current user no longer owns the target',
  async () => {
    const service =
      createPushRegistrationService({
        registrationModel: {
          async deleteOne() {
            return {
              deletedCount: 0
            };
          }
        }
      });

    assert.deepEqual(
      await service.unregister({
        userId: 'user-1',
        targetKind: 'fid',
        target:
          'firebase-installation-id-123456'
      }),
      { unregistered: false }
    );
  }
);

test(
  'internal delivery lookup explicitly selects hidden target',
  async () => {
    const observed = {
      filter: null,
      select: null,
      sort: null
    };

    const query = {
      select(value) {
        observed.select = value;
        return this;
      },
      sort(value) {
        observed.sort = value;
        return this;
      },
      async lean() {
        return [
          {
            targetKind: 'token',
            target:
              'registration-token-1234567890',
            platform: 'android'
          }
        ];
      }
    };

    const service =
      createPushRegistrationService({
        registrationModel: {
          find(filter) {
            observed.filter = filter;
            return query;
          }
        }
      });

    const targets =
      await service.listDeliveryTargetsForUser(
        'user-1'
      );

    assert.deepEqual(
      observed.filter,
      { user: 'user-1' }
    );

    assert.equal(
      observed.select,
      '+target'
    );

    assert.deepEqual(
      observed.sort,
      {
        updatedAt: -1,
        _id: -1
      }
    );

    assert.equal(targets.length, 1);
  }
);

test(
  'push routes authenticate before register and unregister handlers',
  () => {
    const source = fs.readFileSync(
      new URL(
        '../src/routes/push-registration.routes.js',
        import.meta.url
      ),
      'utf8'
    );

    const authIndex =
      source.indexOf(
        'router.use(requireAuth)'
      );

    const putIndex =
      source.indexOf("router.put(");

    const deleteIndex =
      source.indexOf("router.delete(");

    assert.ok(authIndex >= 0);
    assert.ok(putIndex > authIndex);
    assert.ok(deleteIndex > authIndex);

    assert.match(
      source,
      /'\/registrations'/
    );
  }
);

test(
  'push controller never reads client-supplied account identity',
  () => {
    const source = fs.readFileSync(
      new URL(
        '../src/controllers/push-registration.controller.js',
        import.meta.url
      ),
      'utf8'
    );

    assert.match(
      source,
      /userId:\s*req\.user\._id/
    );

    assert.doesNotMatch(
      source,
      /req\.body\.user(?:Id)?/
    );

    assert.doesNotMatch(
      source,
      /target:\s*registration\.target/
    );
  }
);

test(
  'terminal delivery cleanup is fenced by registration, owner and exact target',
  async () => {
    let observedFilter;

    const service =
      createPushRegistrationService({
        registrationModel: {
          async deleteOne(filter) {
            observedFilter = filter;

            return {
              deletedCount: 1
            };
          }
        }
      });

    const removed =
      await service.removeDeliveryTarget({
        registrationId:
          'registration-1',
        userId:
          'observed-owner',
        targetKind:
          'token',
        target:
          'registration-token-1234567890'
      });

    assert.equal(
      removed,
      true
    );

    assert.deepEqual(
      observedFilter,
      {
        _id:
          'registration-1',
        user:
          'observed-owner',
        targetKind:
          'token',
        target:
          'registration-token-1234567890'
      }
    );
  }
);
