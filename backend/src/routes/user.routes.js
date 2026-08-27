import { Router } from 'express';

import {
  getMyNotificationPreferences,
  updateMe,
  updateMyNotificationPreferences
} from '../controllers/user.controller.js';
import { getMyRecommendations } from '../controllers/recommendation.controller.js';
import { requireAuth } from '../middleware/auth.js';
import { validateProfilePatch } from '../middleware/validate.js';

const router = Router();

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
