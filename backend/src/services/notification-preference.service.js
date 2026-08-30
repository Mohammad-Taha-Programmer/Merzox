import { AppError } from '../utils/AppError.js';

/**
 * The notification preferences a person may set.
 *
 * `productOffers` is the customer's; `orderUpdates` is the merchant's, which
 * `البروفايل` puts at the foot of the merchant menu. They are separate keys
 * because they are separate decisions: a shop owner silencing marketing must
 * not also silence the notice that an order arrived.
 *
 * Both default to on, and both default to on for a document written before
 * either existed — an absent value is not a refusal.
 */
export const NOTIFICATION_PREFERENCES = Object.freeze([
  'productOffers',
  'orderUpdates'
]);

export function notificationPreferenceView(user) {
  const stored = user?.notificationPreferences;

  return {
    productOffers: stored?.productOffers !== false,
    orderUpdates: stored?.orderUpdates !== false
  };
}

/**
 * Reads the single preference a PATCH is setting.
 *
 * Deliberately still exactly one key per request: a body carrying two would
 * make a partial failure ambiguous, and there is no screen that changes both
 * at once. The key must be one this service knows — an unrecognised one is
 * refused rather than stored and forgotten.
 */
export function parseNotificationPreferencePatch(body) {
  const keys =
    body && typeof body === 'object' && !Array.isArray(body)
      ? Object.keys(body)
      : [];

  const [key] = keys;
  if (
    keys.length !== 1 ||
    !NOTIFICATION_PREFERENCES.includes(key) ||
    typeof body[key] !== 'boolean'
  ) {
    throw new AppError(
      `Exactly one of ${NOTIFICATION_PREFERENCES.join(', ')} must be sent, ` +
        'and it must be boolean',
      400,
      'INVALID_NOTIFICATION_PREFERENCE'
    );
  }

  return { key, value: body[key] };
}

export async function updateNotificationPreference({ user, key, value }) {
  if (!NOTIFICATION_PREFERENCES.includes(key) || typeof value !== 'boolean') {
    throw new AppError(
      'Notification preference is invalid',
      400,
      'INVALID_NOTIFICATION_PREFERENCE'
    );
  }

  user.notificationPreferences ??= {};
  user.notificationPreferences[key] = value;

  await user.save();

  return notificationPreferenceView(user);
}

/**
 * The pre-`orderUpdates` entry point, kept so nothing that called it breaks.
 *
 * @deprecated Use {@link updateNotificationPreference}.
 */
export async function updateProductOffersPreference({ user, productOffers }) {
  return updateNotificationPreference({
    user,
    key: 'productOffers',
    value: productOffers
  });
}
