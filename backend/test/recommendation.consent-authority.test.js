import assert from 'node:assert/strict';
import test from 'node:test';

import { validateProfilePatch } from '../src/middleware/validate.js';
import {
  hasRecommendationConsent,
  recommendationConsentStatus,
  recommendationConsentView
} from '../src/policies/recommendation.policy.js';

function validate(body) {
  let nextCalled = false;

  validateProfilePatch(
    { body },
    {},
    () => {
      nextCalled = true;
    }
  );

  return nextCalled;
}

function assertCode(fn, code) {
  assert.throws(
    fn,
    (error) => {
      assert.equal(error?.code, code);
      assert.equal(error?.statusCode, 400);
      return true;
    }
  );
}

test('recommendation authority requires permission true and granted consent together', () => {
  const user = {
    permissions: {
      aiPersonalization: true
    },
    permissionConsents: {
      aiPersonalization: {
        status: 'granted'
      }
    }
  };

  assert.equal(hasRecommendationConsent(user), true);
  assert.deepEqual(
    recommendationConsentView(user),
    {
      enabled: true,
      status: 'granted'
    }
  );
});

test('permission true cannot bypass denied or missing consent', () => {
  for (const status of [
    'denied',
    'notAsked',
    undefined,
    'unexpected'
  ]) {
    const user = {
      permissions: {
        aiPersonalization: true
      },
      permissionConsents: {
        aiPersonalization: {
          status
        }
      }
    };

    assert.equal(
      hasRecommendationConsent(user),
      false,
      `status=${String(status)}`
    );
  }
});

test('granted consent cannot bypass a disabled or missing permission boolean', () => {
  for (const permission of [
    false,
    undefined,
    'true',
    1
  ]) {
    const user = {
      permissions: {
        aiPersonalization: permission
      },
      permissionConsents: {
        aiPersonalization: {
          status: 'granted'
        }
      }
    };

    assert.equal(
      hasRecommendationConsent(user),
      false,
      `permission=${String(permission)}`
    );
  }
});

test('malformed or absent consent state fails closed to notAsked', () => {
  assert.equal(
    recommendationConsentStatus({}),
    'notAsked'
  );

  assert.equal(
    recommendationConsentStatus({
      permissionConsents: {
        aiPersonalization: {
          status: 'invalid'
        }
      }
    }),
    'notAsked'
  );

  assert.deepEqual(
    recommendationConsentView({
      permissions: {
        aiPersonalization: true
      }
    }),
    {
      enabled: false,
      status: 'notAsked'
    }
  );
});

test('profile patch accepts only the three known boolean permission keys', () => {
  assert.equal(
    validate({
      permissions: {
        aiPersonalization: true,
        location: false,
        contacts: true
      }
    }),
    true
  );

  assert.equal(
    validate({
      permissions: {}
    }),
    true
  );
});

test('profile patch rejects non-object permissions', () => {
  for (const permissions of [
    null,
    true,
    false,
    'true',
    [],
    1
  ]) {
    assertCode(
      () => validate({ permissions }),
      'INVALID_PROFILE_PERMISSIONS'
    );
  }
});

test('profile patch rejects unknown nested permission keys', () => {
  assertCode(
    () =>
      validate({
        permissions: {
          aiPersonalization: true,
          recommendationTracking: true
        }
      }),
    'INVALID_PROFILE_PERMISSION_FIELDS'
  );
});

test('profile patch rejects non-boolean permission values before controller mutation', () => {
  for (const value of [
    'true',
    'false',
    1,
    0,
    null,
    {}
  ]) {
    assertCode(
      () =>
        validate({
          permissions: {
            aiPersonalization: value
          }
        }),
      'INVALID_PROFILE_PERMISSION_VALUE'
    );
  }
});
