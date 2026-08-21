import { Router } from 'express';

import { updateMe } from '../controllers/user.controller.js';
import { requireAuth } from '../middleware/auth.js';
import { validateProfilePatch } from '../middleware/validate.js';

const router = Router();

router.patch('/me', requireAuth, validateProfilePatch, updateMe);

export default router;
