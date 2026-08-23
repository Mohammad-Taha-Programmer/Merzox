import { AppError } from '../utils/AppError.js';

export function notificationPreferenceView(user) {
  return {
    productOffers: user?.notificationPreferences?.productOffers !== false
  };
}

export function parseNotificationPreferencePatch(body) {
  if (
    !body ||
    typeof body !== 'object' ||
    Array.isArray(body) ||
    Object.keys(body).length !== 1 ||
    !Object.hasOwn(body, 'productOffers') ||
    typeof body.productOffers !== 'boolean'
  ) {
    throw new AppError(
      'productOffers must be the only preference and must be boolean',
      400,
      'INVALID_NOTIFICATION_PREFERENCE'
    );
  }

  return body.productOffers;
}

export async function updateProductOffersPreference({
  user,
  productOffers
}) {
  if (typeof productOffers !== 'boolean') {
    throw new AppError(
      'productOffers must be boolean',
      400,
      'INVALID_NOTIFICATION_PREFERENCE'
    );
  }

  user.notificationPreferences ??= {};
  user.notificationPreferences.productOffers = productOffers;

  await user.save();

  return notificationPreferenceView(user);
}
