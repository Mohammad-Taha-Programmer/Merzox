import { Router } from 'express';

import {
  forgotPassword,
  login,
  logout,
  me,
  resetPassword,
  signup,
  verifyEmail
} from '../controllers/auth.controller.js';
import { requireAuth } from '../middleware/auth.js';
import {
  forgotPasswordLimiter,
  resetPasswordLimiter
} from '../middleware/security.js';
import {
  validateForgotPassword,
  validateLogin,
  validateResetPassword,
  validateSignup
} from '../middleware/validate.js';

const router = Router();

router.post('/signup', validateSignup, signup);
router.get('/verify-email', verifyEmail);
router.post('/login', validateLogin, login);
router.post(
  '/forgot-password',
  validateForgotPassword,
  forgotPasswordLimiter,
  forgotPassword
);
router.post(
  '/reset-password',
  validateResetPassword,
  resetPasswordLimiter,
  resetPassword
);
router.get('/me', requireAuth, me);
router.post('/logout', requireAuth, logout);

export default router;
