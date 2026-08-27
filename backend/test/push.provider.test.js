import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

import {
  buildPushMessage,
  firebasePushInitFailureLog,
  isTerminalPushTargetError,
  pushDeliveryFailureLog,
  registerPushSender,
  sendPushTarget
} from '../src/push/push.publisher.js';
import {
  createFirebasePushProvider
} from '../src/push/firebase-push.provider.js';

test(
  'push message carries display copy and minimal REST routing metadata only',
  () => {
    const message =
      buildPushMessage({
        _id: 'notification-123',
        audience: 'customer',
        type: 'orderStatus',
        business: 'business-123',
        title: 'Order updated',
        body: 'Your order changed',
        data: {
          orderId: 'order-123',
          publicId:
            'PRIVATE-PUBLIC-ID',
          total: 999,
          status: 'delivered',
          senderName:
            'PRIVATE-SENDER',
          reviewerName:
            'PRIVATE-REVIEWER'
        }
      });

    assert.deepEqual(
      message,
      {
        notification: {
          title: 'Order updated',
          body:
            'Your order changed'
        },
        data: {
          notificationId:
            'notification-123',
          audience: 'customer',
          type: 'orderStatus',
          businessId:
            'business-123',
          routeKind: 'order',
          orderId: 'order-123'
        }
      }
    );

    const serialized =
      JSON.stringify(message);

    for (
      const secret of [
        'PRIVATE-PUBLIC-ID',
        'PRIVATE-SENDER',
        'PRIVATE-REVIEWER',
        '999',
        'delivered'
      ]
    ) {
      assert.equal(
        serialized.includes(secret),
        false
      );
    }
  }
);

test(
  'conversation routing wins when conversation metadata exists',
  () => {
    const message =
      buildPushMessage({
        _id: 'notification-1',
        audience: 'business',
        type: 'newMessage',
        business: 'business-1',
        title: 'New message',
        body: 'Open chat',
        data: {
          conversationId:
            'conversation-1',
          orderId:
            'must-not-leak'
        }
      });

    assert.equal(
      message.data.routeKind,
      'conversation'
    );

    assert.equal(
      message.data.conversationId,
      'conversation-1'
    );

    assert.equal(
      Object.hasOwn(
        message.data,
        'orderId'
      ),
      false
    );
  }
);

test(
  'invalid persisted-looking notification input is refused',
  () => {
    assert.equal(
      buildPushMessage({
        audience: 'customer',
        type: 'orderStatus',
        title: 'x',
        body: 'y'
      }),
      null
    );

    assert.equal(
      buildPushMessage({
        _id: 'n-1',
        audience: 'attacker',
        type: 'orderStatus',
        title: 'x',
        body: 'y'
      }),
      null
    );
  }
);

test(
  'push sender is disabled until a provider registers it',
  async () => {
    assert.deepEqual(
      await sendPushTarget({
        targetKind: 'token',
        target:
          'registration-token-123456',
        message: {
          data: {
            x: '1'
          }
        }
      }),
      {
        sent: false,
        reason: 'disabled'
      }
    );
  }
);

test(
  'registered sender supports transport without exposing target in result',
  async () => {
    const calls = [];

    const unregister =
      registerPushSender(
        async (request) => {
          calls.push(request);
          return 'message-id-1';
        }
      );

    try {
      const result =
        await sendPushTarget({
          targetKind: 'token',
          target:
            'registration-token-123456',
          message: {
            data: {
              x: '1'
            }
          }
        });

      assert.deepEqual(
        result,
        {
          sent: true,
          messageId:
            'message-id-1'
        }
      );

      assert.equal(
        calls.length,
        1
      );
    } finally {
      unregister();
    }
  }
);

test(
  'only explicit invalid or unregistered token errors are terminal',
  () => {
    for (
      const code of [
        'messaging/registration-token-not-registered',
        'messaging/invalid-registration-token'
      ]
    ) {
      assert.equal(
        isTerminalPushTargetError({
          code
        }),
        true,
        code
      );
    }

    for (
      const code of [
        'messaging/server-unavailable',
        'messaging/internal-error',
        'messaging/message-rate-exceeded',
        'messaging/authentication-error',
        'messaging/mismatched-credential',
        'messaging/invalid-argument',
        'messaging/invalid-recipient'
      ]
    ) {
      assert.equal(
        isTerminalPushTargetError({
          code
        }),
        false,
        code
      );
    }
  }
);

test(
  'push delivery failure log contains no target, content or error message',
  () => {
    const secret =
      'VERY-PRIVATE-TARGET-123';

    const error =
      new Error(
        `failed for ${secret}`
      );

    error.name =
      'FirebaseMessagingError';

    error.code =
      'messaging/server-unavailable';

    const line =
      pushDeliveryFailureLog(
        {
          notificationType:
            'newMessage',
          targetKind:
            'token',
          platform:
            'android',
          target:
            secret
        },
        error
      ).join(' ');

    assert.equal(
      line.includes(secret),
      false
    );

    assert.equal(
      line.includes(
        'failed for'
      ),
      false
    );

    assert.equal(
      line.includes(
        'PUSH_DELIVERY_FAILED'
      ),
      true
    );
  }
);

test(
  'Firebase initialization failure log is fixed and credential-safe',
  () => {
    const secret =
      'C:/secret/firebase.json';

    const error =
      new Error(secret);

    error.name =
      'CredentialError';

    const line =
      firebasePushInitFailureLog(
        error
      ).join(' ');

    assert.equal(
      line.includes(secret),
      false
    );

    assert.equal(
      line.includes(
        'FIREBASE_INIT_FAILED'
      ),
      true
    );
  }
);

test(
  'disabled Firebase provider performs zero SDK initialization work',
  () => {
    let calls = 0;

    const provider =
      createFirebasePushProvider({
        enabled: false,
        getAppsFn() {
          calls += 1;
          return [];
        },
        initializeAppFn() {
          calls += 1;
          return {};
        },
        applicationDefaultFn() {
          calls += 1;
          return {};
        },
        getMessagingFn() {
          calls += 1;
          return {};
        },
        registerPushSenderFn() {
          calls += 1;
          return () => {};
        }
      });

    assert.deepEqual(
      provider.initialize(),
      {
        enabled: false,
        initialized: false
      }
    );

    assert.equal(calls, 0);
  }
);

test(
  'enabled provider uses ADC and maps token and fid correctly',
  async () => {
    let adcCalls = 0;
    let initializedOptions;
    let registeredSender;

    const messages = [];

    const fakeApp = {
      name: '[DEFAULT]'
    };

    const provider =
      createFirebasePushProvider({
        enabled: true,
        nodeEnv: 'test',

        getAppsFn() {
          return [];
        },

        applicationDefaultFn() {
          adcCalls += 1;

          return {
            kind:
              'adc-credential'
          };
        },

        initializeAppFn(options) {
          initializedOptions =
            options;

          return fakeApp;
        },

        getMessagingFn(app) {
          assert.equal(
            app,
            fakeApp
          );

          return {
            async send(message) {
              messages.push(message);

              return (
                `message-${messages.length}`
              );
            }
          };
        },

        registerPushSenderFn(
          sender
        ) {
          registeredSender =
            sender;

          return () => {};
        }
      });

    assert.deepEqual(
      provider.initialize(),
      {
        enabled: true,
        initialized: true
      }
    );

    assert.equal(
      adcCalls,
      1
    );

    assert.deepEqual(
      initializedOptions,
      {
        credential: {
          kind:
            'adc-credential'
        }
      }
    );

    await registeredSender({
      targetKind: 'token',
      target: 'token-123',
      message: {
        data: {
          a: '1'
        }
      }
    });

    await registeredSender({
      targetKind: 'fid',
      target: 'fid-123',
      message: {
        data: {
          b: '2'
        }
      }
    });

    assert.deepEqual(
      messages[0],
      {
        data: {
          a: '1'
        },
        token: 'token-123'
      }
    );

    assert.deepEqual(
      messages[1],
      {
        data: {
          b: '2'
        },
        fid: 'fid-123'
      }
    );

    provider.close();
  }
);

test(
  'existing default Firebase app is reused without reading ADC',
  () => {
    const existingApp = {
      name: '[DEFAULT]'
    };

    let adcCalls = 0;
    let initCalls = 0;

    const provider =
      createFirebasePushProvider({
        enabled: true,
        nodeEnv: 'test',

        getAppsFn() {
          return [
            existingApp
          ];
        },

        applicationDefaultFn() {
          adcCalls += 1;
          return {};
        },

        initializeAppFn() {
          initCalls += 1;
          return {};
        },

        getMessagingFn(app) {
          assert.equal(
            app,
            existingApp
          );

          return {
            async send() {
              return 'x';
            }
          };
        },

        registerPushSenderFn() {
          return () => {};
        }
      });

    assert.equal(
      provider.initialize()
        .initialized,
      true
    );

    assert.equal(adcCalls, 0);
    assert.equal(initCalls, 0);

    provider.close();
  }
);

test(
  'provider initialization failure is non-fatal',
  () => {
    const provider =
      createFirebasePushProvider({
        enabled: true,
        nodeEnv: 'test',

        getAppsFn() {
          return [];
        },

        applicationDefaultFn() {
          throw new Error(
            'credentials absent'
          );
        }
      });

    assert.deepEqual(
      provider.initialize(),
      {
        enabled: true,
        initialized: false
      }
    );
  }
);

test(
  'server wiring remains opt-in and no credential file is hard-coded',
  () => {
    const server =
      fs.readFileSync(
        new URL(
          '../src/server.js',
          import.meta.url
        ),
        'utf8'
      );

    const environment =
      fs.readFileSync(
        new URL(
          '../src/config/environment.js',
          import.meta.url
        ),
        'utf8'
      );

    const provider =
      fs.readFileSync(
        new URL(
          '../src/push/firebase-push.provider.js',
          import.meta.url
        ),
        'utf8'
      );

    assert.match(
      server,
      /initializeFirebasePushProvider\(\)/
    );

    assert.match(
      environment,
      /FIREBASE_PUSH_ENABLED/
    );

    assert.match(
      provider,
      /applicationDefault/
    );

    assert.doesNotMatch(
      provider,
      /service[-_ ]?account.*\.json/i
    );

    assert.doesNotMatch(
      provider,
      /readFileSync/
    );
  }
);
