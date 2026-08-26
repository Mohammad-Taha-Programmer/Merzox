import {
  normalizePushTarget,
  PUSH_PLATFORMS,
  PUSH_TARGET_KINDS
} from '../policies/push-registration.policy.js';
import { AppError } from '../utils/AppError.js';

function exactBody(body, allowed, code) {
  if (
    !body ||
    typeof body !== 'object' ||
    Array.isArray(body)
  ) {
    throw new AppError(
      'Push registration fields are invalid',
      400,
      code
    );
  }

  const keys = Object.keys(body);

  if (
    keys.length !== allowed.length ||
    keys.some((key) => !allowed.includes(key))
  ) {
    throw new AppError(
      'Push registration fields are invalid',
      400,
      code
    );
  }
}

function validateTarget(req) {
  if (
    !PUSH_TARGET_KINDS.includes(
      req.body.targetKind
    )
  ) {
    throw new AppError(
      'Push target kind is invalid',
      400,
      'INVALID_PUSH_TARGET_KIND'
    );
  }

  const target =
    normalizePushTarget(req.body.target);

  if (!target) {
    throw new AppError(
      'Push target is invalid',
      400,
      'INVALID_PUSH_TARGET'
    );
  }

  // Store only the normalized opaque value.
  req.body.target = target;
}

export function validatePushRegistrationUpsert(
  req,
  _res,
  next
) {
  exactBody(
    req.body,
    [
      'targetKind',
      'target',
      'platform'
    ],
    'INVALID_PUSH_REGISTRATION_FIELDS'
  );

  validateTarget(req);

  if (
    !PUSH_PLATFORMS.includes(
      req.body.platform
    )
  ) {
    throw new AppError(
      'Push platform is invalid',
      400,
      'INVALID_PUSH_PLATFORM'
    );
  }

  next();
}

export function validatePushRegistrationDelete(
  req,
  _res,
  next
) {
  exactBody(
    req.body,
    [
      'targetKind',
      'target'
    ],
    'INVALID_PUSH_REGISTRATION_FIELDS'
  );

  validateTarget(req);
  next();
}
