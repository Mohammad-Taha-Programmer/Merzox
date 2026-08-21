import { Router } from 'express';

import { login, logout, me, signup, verifyEmail } from '../controllers/auth.controller.js';
import { requireAuth } from '../middleware/auth.js';
import { validateLogin, validateSignup } from '../middleware/validate.js';

const router = Router();

router.post('/signup', validateSignup, signup);
router.get('/verify-email', verifyEmail);
router.post('/login', validateLogin, login);
router.get('/me', requireAuth, me);
router.post('/logout', requireAuth, logout);

export default router;
