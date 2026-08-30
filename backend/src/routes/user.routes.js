import { Router } from 'express';

import {
  getMyNotificationPreferences,
  updateMe,
  updateMyNotificationPreferences
} from '../controllers/user.controller.js';
import {
  createMyAddress,
  deleteMyAddress,
  listDeliveryRegions,
  listMyAddresses,
  setMyDefaultAddress,
  updateMyAddress
} from '../controllers/address.controller.js';
import { getMyRecommendations } from '../controllers/recommendation.controller.js';
import { requireAuth } from '../middleware/auth.js';
import { validateProfilePatch } from '../middleware/validate.js';

const router = Router();

// Public: where the company delivers is not private, and the checkout form
// needs the list before anyone has signed in to fill it.
router.get('/delivery-regions', listDeliveryRegions);

// Everything below reaches its data through req.user, never through an id in
// the path, so one account cannot name another account's address.
router.get('/me/addresses', requireAuth, listMyAddresses);
router.post('/me/addresses', requireAuth, createMyAddress);
router.patch('/me/addresses/:addressId', requireAuth, updateMyAddress);
router.patch(
  '/me/addresses/:addressId/default',
  requireAuth,
  setMyDefaultAddress
);
router.delete('/me/addresses/:addressId', requireAuth, deleteMyAddress);

router.get(
  '/me/notification-preferences',
  requireAuth,
  getMyNotificationPreferences
);
router.patch(
  '/me/notification-preferences',
  requireAuth,
  updateMyNotificationPreferences
);
router.get(
  '/me/recommendations',
  requireAuth,
  getMyRecommendations
);
router.patch('/me', requireAuth, validateProfilePatch, updateMe);

export default router;
