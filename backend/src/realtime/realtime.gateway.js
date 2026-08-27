import { Server } from 'socket.io';

import { env } from '../config/env.js';
import { User } from '../models/User.js';
import { registerRealtimeEmitter } from './realtime.publisher.js';
import {
  isAccessTokenCurrent,
  verifyAccessToken
} from '../utils/jwt.js';

export const realtimeAuthCodes = Object.freeze({
  required: 'AUTH_REQUIRED',
  invalid: 'AUTH_INVALID'
});

function realtimeAuthError(code, message) {
  const error = new Error(message);
  error.data = { code };
  return error;
}

export function realtimeUserRoom(userId) {
  const id = String(userId ?? '').trim();

  if (!id) {
    throw new TypeError('Realtime user id is required');
  }

  return `user:${id}`;
}

export function isRealtimeOriginAllowed(
  origin,
  allowedOrigins = env.corsOrigins
) {
  if (!origin) {
    return true;
  }

  return allowedOrigins.some((allowed) => {
    if (allowed.endsWith('*')) {
      return origin.startsWith(
        allowed.slice(0, -1)
      );
    }

    return origin === allowed;
  });
}

export function createRealtimeAuthenticator({
  verifyToken = verifyAccessToken,
  findUserById = (id) => User.findById(id),
  isTokenCurrent = isAccessTokenCurrent
} = {}) {
  return async function authenticateRealtimeSocket(socket) {
    const rawToken =
      socket.handshake?.auth?.token;

    const token =
      typeof rawToken === 'string'
        ? rawToken.trim()
        : '';

    if (!token) {
      throw realtimeAuthError(
        realtimeAuthCodes.required,
        'Authentication required'
      );
    }

    let payload;

    try {
      payload = verifyToken(token);
    } catch (_) {
      throw realtimeAuthError(
        realtimeAuthCodes.invalid,
        'Authentication failed'
      );
    }

    const subject =
      typeof payload?.sub === 'string'
        ? payload.sub.trim()
        : '';

    if (!subject) {
      throw realtimeAuthError(
        realtimeAuthCodes.invalid,
        'Authentication failed'
      );
    }

    let user;

    try {
      user = await findUserById(subject);
    } catch (_) {
      throw realtimeAuthError(
        realtimeAuthCodes.invalid,
        'Authentication failed'
      );
    }

    if (
      !user ||
      !user.isActive ||
      !isTokenCurrent(payload, user)
    ) {
      throw realtimeAuthError(
        realtimeAuthCodes.invalid,
        'Authentication failed'
      );
    }

    return user;
  };
}

export const authenticateRealtimeSocket =
  createRealtimeAuthenticator();

export function createRealtimeAuthMiddleware(
  authenticate = authenticateRealtimeSocket
) {
  return async function realtimeAuthMiddleware(
    socket,
    next
  ) {
    try {
      const user = await authenticate(socket);

      socket.data.auth = {
        userId: user._id.toString(),
        userType: user.userType
      };

      next();
    } catch (error) {
      if (
        error?.data?.code ===
          realtimeAuthCodes.required ||
        error?.data?.code ===
          realtimeAuthCodes.invalid
      ) {
        next(error);
        return;
      }

      next(
        realtimeAuthError(
          realtimeAuthCodes.invalid,
          'Authentication failed'
        )
      );
    }
  };
}

const realtimeCloseHandlers = new WeakMap();

export function createRealtimeServer(
  httpServer,
  {
    authenticate = authenticateRealtimeSocket
  } = {}
) {
  const io = new Server(httpServer, {
    cors: {
      origin(origin, callback) {
        callback(
          null,
          isRealtimeOriginAllowed(origin)
        );
      },
      credentials: true
    }
  });

  const unregisterRealtimeEmitter =
    registerRealtimeEmitter((userId, event, payload) => {
      io.to(realtimeUserRoom(userId)).emit(event, payload);
    });

  realtimeCloseHandlers.set(
    io,
    unregisterRealtimeEmitter
  );

  io.use(
    createRealtimeAuthMiddleware(authenticate)
  );

  io.on('connection', (socket) => {
    socket.join(
      realtimeUserRoom(
        socket.data.auth.userId
      )
    );
  });

  return io;
}

export function closeRealtimeServer(io) {
  const unregister =
    realtimeCloseHandlers.get(io);

  realtimeCloseHandlers.delete(io);

  if (unregister) {
    unregister();
  }

  return new Promise((resolve) => {
    io.close(() => {
      resolve();
    });
  });
}
