import { User } from '../models/User.js';
import { AppError } from '../utils/AppError.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { verifyAccessToken } from '../utils/jwt.js';

export const requireAuth = asyncHandler(async (req, _res, next) => {
  const header = req.get('authorization') ?? '';
  const [scheme, token] = header.split(' ');

  if (scheme !== 'Bearer' || !token) {
    throw new AppError('Authentication required', 401, 'AUTH_REQUIRED');
  }

  const payload = verifyAccessToken(token);
  const user = await User.findById(payload.sub);

  if (!user || !user.isActive) {
    throw new AppError('User account is not available', 401, 'AUTH_INVALID');
  }

  req.user = user;
  next();
});

export function requireBusinessUser(req, _res, next) {
  if (!req.user || req.user.userType !== 'business') {
    throw new AppError('A business account is required', 403, 'BUSINESS_ACCOUNT_REQUIRED');
  }

  next();
}
