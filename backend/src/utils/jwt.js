import jwt from 'jsonwebtoken';

import { env } from '../config/env.js';

export function signAccessToken(user) {
  return jwt.sign(
    {
      sub: user._id.toString(),
      userType: user.userType,
      authVersion: Number(user.authVersion ?? 0)
    },
    env.jwtSecret,
    { expiresIn: env.jwtExpiresIn }
  );
}

export function isAccessTokenCurrent(payload, user) {
  const tokenVersion = Number(payload?.authVersion ?? 0);
  const userVersion = Number(user?.authVersion ?? 0);

  return (
    Number.isSafeInteger(tokenVersion) &&
    tokenVersion >= 0 &&
    Number.isSafeInteger(userVersion) &&
    userVersion >= 0 &&
    tokenVersion === userVersion
  );
}

export function verifyAccessToken(token) {
  return jwt.verify(token, env.jwtSecret);
}
