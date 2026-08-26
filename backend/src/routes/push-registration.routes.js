import { Router } from 'express';

import {
  registerPushRegistration,
  unregisterPushRegistration
} from '../controllers/push-registration.controller.js';
import { requireAuth } from '../middleware/auth.js';
import {
  validatePushRegistrationDelete,
  validatePushRegistrationUpsert
} from '../middleware/push-registration.validate.js';

const router = Router();

router.use(requireAuth);

router.put(
  '/registrations',
  validatePushRegistrationUpsert,
  registerPushRegistration
);

router.delete(
  '/registrations',
  validatePushRegistrationDelete,
  unregisterPushRegistration
);

export default router;
