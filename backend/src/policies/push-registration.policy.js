export const PUSH_TARGET_KINDS = Object.freeze([
  'token',
  'fid'
]);

export const PUSH_PLATFORMS = Object.freeze([
  'android',
  'ios'
]);

export const PUSH_TARGET_MIN_LENGTH = 16;
export const PUSH_TARGET_MAX_LENGTH = 4096;

/**
 * Push targets are opaque transport identifiers.
 *
 * Do not impose provider-specific punctuation rules here. FCM registration
 * tokens and FIDs have different shapes and both are supported during the
 * Firebase migration period.
 */
export function normalizePushTarget(value) {
  if (typeof value !== 'string') {
    return null;
  }

  const target = value.trim();

  if (
    target.length < PUSH_TARGET_MIN_LENGTH ||
    target.length > PUSH_TARGET_MAX_LENGTH ||
    /\s/.test(target)
  ) {
    return null;
  }

  return target;
}
