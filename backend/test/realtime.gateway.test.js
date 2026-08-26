import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createRealtimeAuthenticator,
  createRealtimeAuthMiddleware,
  isRealtimeOriginAllowed,
  realtimeAuthCodes,
  realtimeUserRoom
} from '../src/realtime/realtime.gateway.js';

function socketWithToken(token) {
  return {
    handshake: {
      auth: { token }
    },
    data: {}
  };
}

function activeUser({
  id = 'user-1',
  userType = 'normal',
  authVersion = 0
} = {}) {
  return {
    _id: {
      toString() {
        return id;
      }
    },
    userType,
    authVersion,
    isActive: true
  };
}

test(
  'realtime room is derived only from server user id',
  () => {
    assert.equal(
      realtimeUserRoom('abc123'),
      'user:abc123'
    );

    assert.throws(
      () => realtimeUserRoom(''),
      /Realtime user id is required/
    );
  }
);

test(
  'realtime CORS follows exact and wildcard origins',
  () => {
    const allowed = [
      'https://merzox.example',
      'http://localhost:*'
    ];

    assert.equal(
      isRealtimeOriginAllowed(
        undefined,
        allowed
      ),
      true
    );

    assert.equal(
      isRealtimeOriginAllowed(
        'https://merzox.example',
        allowed
      ),
      true
    );

    assert.equal(
      isRealtimeOriginAllowed(
        'http://localhost:8080',
        allowed
      ),
      true
    );

    assert.equal(
      isRealtimeOriginAllowed(
        'https://evil.example',
        allowed
      ),
      false
    );
  }
);

test(
  'realtime authentication refuses a missing token',
  async () => {
    const authenticate =
      createRealtimeAuthenticator({
        verifyToken() {
          throw new Error(
            'verify must not run'
          );
        }
      });

    await assert.rejects(
      () => authenticate(socketWithToken('')),
      (error) => {
        assert.equal(
          error.data?.code,
          realtimeAuthCodes.required
        );

        return true;
      }
    );
  }
);

test(
  'realtime authentication refuses an invalid JWT',
  async () => {
    const authenticate =
      createRealtimeAuthenticator({
        verifyToken() {
          throw new Error('bad token');
        }
      });

    await assert.rejects(
      () =>
        authenticate(
          socketWithToken('invalid')
        ),
      (error) => {
        assert.equal(
          error.data?.code,
          realtimeAuthCodes.invalid
        );

        return true;
      }
    );
  }
);

test(
  'realtime authentication refuses missing, inactive, and stale users',
  async (t) => {
    await t.test(
      'missing user',
      async () => {
        const authenticate =
          createRealtimeAuthenticator({
            verifyToken() {
              return {
                sub: 'user-1',
                authVersion: 0
              };
            },
            async findUserById() {
              return null;
            }
          });

        await assert.rejects(
          () =>
            authenticate(
              socketWithToken('token')
            ),
          (error) => {
            assert.equal(
              error.data?.code,
              realtimeAuthCodes.invalid
            );

            return true;
          }
        );
      }
    );

    await t.test(
      'inactive user',
      async () => {
        const authenticate =
          createRealtimeAuthenticator({
            verifyToken() {
              return {
                sub: 'user-1',
                authVersion: 0
              };
            },
            async findUserById() {
              return {
                ...activeUser(),
                isActive: false
              };
            }
          });

        await assert.rejects(
          () =>
            authenticate(
              socketWithToken('token')
            ),
          (error) => {
            assert.equal(
              error.data?.code,
              realtimeAuthCodes.invalid
            );

            return true;
          }
        );
      }
    );

    await t.test(
      'stale auth version',
      async () => {
        const authenticate =
          createRealtimeAuthenticator({
            verifyToken() {
              return {
                sub: 'user-1',
                authVersion: 4
              };
            },
            async findUserById() {
              return activeUser({
                authVersion: 5
              });
            },
            isTokenCurrent(
              payload,
              user
            ) {
              return (
                payload.authVersion ===
                user.authVersion
              );
            }
          });

        await assert.rejects(
          () =>
            authenticate(
              socketWithToken('token')
            ),
          (error) => {
            assert.equal(
              error.data?.code,
              realtimeAuthCodes.invalid
            );

            return true;
          }
        );
      }
    );
  }
);

test(
  'realtime middleware stores only server-derived identity',
  async () => {
    const socket = socketWithToken(
      'client-token'
    );

    socket.handshake.auth.userId =
      'attacker-controlled-id';

    const middleware =
      createRealtimeAuthMiddleware(
        async () =>
          activeUser({
            id: 'server-user-id',
            userType: 'business'
          })
      );

    let nextError = Symbol(
      'not-called'
    );

    await middleware(
      socket,
      (error) => {
        nextError = error;
      }
    );

    assert.equal(
      nextError,
      undefined
    );

    assert.deepEqual(
      socket.data.auth,
      {
        userId: 'server-user-id',
        userType: 'business'
      }
    );
  }
);

test(
  'realtime middleware exposes only stable authentication codes',
  async () => {
    const middleware =
      createRealtimeAuthMiddleware(
        async () => {
          throw new Error(
            'database internals'
          );
        }
      );

    let nextError;

    await middleware(
      socketWithToken('token'),
      (error) => {
        nextError = error;
      }
    );

    assert.equal(
      nextError.message,
      'Authentication failed'
    );

    assert.deepEqual(
      nextError.data,
      {
        code:
          realtimeAuthCodes.invalid
      }
    );
  }
);
