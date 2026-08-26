import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

import {
  createPushDeliveryService,
  pushPipelineFailureLog,
  pushRegistryLookupFailureLog,
  pushTargetCleanupFailureLog
} from '../src/push/push.delivery.js';

function notification() {
  return {
    _id: 'notification-1',
    user: 'user-1',
    audience: 'customer',
    type: 'newMessage',
    business: 'business-1',
    title: 'New message',
    body: 'Open the conversation',
    data: {
      conversationId:
        'conversation-1'
    }
  };
}

function message() {
  return {
    notification: {
      title: 'New message',
      body: 'Open the conversation'
    },
    data: {
      notificationId:
        'notification-1'
    }
  };
}

test(
  'disabled transport performs zero registry work',
  async () => {
    let registryCalls = 0;
    let sendCalls = 0;

    const service =
      createPushDeliveryService({
        transportAvailable:
          () => false,

        registrationService: {
          async listDeliveryTargetsForUser() {
            registryCalls += 1;
            return [];
          }
        },

        buildMessage() {
          throw new Error(
            'must not build'
          );
        },

        async sendTarget() {
          sendCalls += 1;
          return {
            sent: true
          };
        },

        nodeEnv: 'test'
      });

    const result =
      await service.deliver(
        notification()
      );

    assert.equal(
      result.reason,
      'disabled'
    );

    assert.equal(
      registryCalls,
      0
    );

    assert.equal(
      sendCalls,
      0
    );
  }
);

test(
  'one persisted notification is delivered to every registered device',
  async () => {
    const calls = [];

    const service =
      createPushDeliveryService({
        transportAvailable:
          () => true,

        buildMessage:
          () => message(),

        registrationService: {
          async listDeliveryTargetsForUser(
            userId
          ) {
            assert.equal(
              userId,
              'user-1'
            );

            return [
              {
                _id: 'r1',
                targetKind: 'token',
                target:
                  'token-device-111111',
                platform:
                  'android'
              },
              {
                _id: 'r2',
                targetKind: 'fid',
                target:
                  'fid-device-22222222',
                platform:
                  'ios'
              }
            ];
          },

          async removeDeliveryTarget() {
            throw new Error(
              'cleanup must not run'
            );
          }
        },

        async sendTarget(request) {
          calls.push(request);

          return {
            sent: true,
            messageId:
              `message-${calls.length}`
          };
        },

        nodeEnv: 'test'
      });

    const result =
      await service.deliver(
        notification()
      );

    assert.deepEqual(
      result,
      {
        sent: 2,
        failed: 0,
        removed: 0,
        skipped: 0
      }
    );

    assert.equal(
      calls.length,
      2
    );

    assert.deepEqual(
      calls.map(
        (call) =>
          call.targetKind
      ).sort(),
      ['fid', 'token']
    );
  }
);

test(
  'terminal provider failure removes only the exact observed registration',
  async () => {
    const cleanupCalls = [];

    const service =
      createPushDeliveryService({
        transportAvailable:
          () => true,

        buildMessage:
          () => message(),

        registrationService: {
          async listDeliveryTargetsForUser() {
            return [
              {
                _id:
                  'registration-1',
                targetKind:
                  'token',
                target:
                  'dead-token-123456789',
                platform:
                  'android'
              }
            ];
          },

          async removeDeliveryTarget(
            request
          ) {
            cleanupCalls.push(
              request
            );

            return true;
          }
        },

        async sendTarget() {
          return {
            sent: false,
            reason:
              'provider-error',
            terminal: true,
            error:
              Object.assign(
                new Error(
                  'private target must never log'
                ),
                {
                  name:
                    'FirebaseMessagingError',
                  code:
                    'messaging/registration-token-not-registered'
                }
              )
          };
        },

        nodeEnv: 'test'
      });

    const result =
      await service.deliver(
        notification()
      );

    assert.deepEqual(
      result,
      {
        sent: 0,
        failed: 1,
        removed: 1,
        skipped: 0
      }
    );

    assert.deepEqual(
      cleanupCalls,
      [
        {
          registrationId:
            'registration-1',
          userId:
            'user-1',
          targetKind:
            'token',
          target:
            'dead-token-123456789'
        }
      ]
    );
  }
);

test(
  'transient provider failure never removes a registration',
  async () => {
    let cleanupCalls = 0;

    const service =
      createPushDeliveryService({
        transportAvailable:
          () => true,

        buildMessage:
          () => message(),

        registrationService: {
          async listDeliveryTargetsForUser() {
            return [
              {
                _id: 'r1',
                targetKind: 'token',
                target:
                  'live-token-123456789',
                platform:
                  'android'
              }
            ];
          },

          async removeDeliveryTarget() {
            cleanupCalls += 1;
            return true;
          }
        },

        async sendTarget() {
          return {
            sent: false,
            reason:
              'provider-error',
            terminal: false,
            error:
              Object.assign(
                new Error(
                  'server unavailable'
                ),
                {
                  code:
                    'messaging/server-unavailable'
                }
              )
          };
        },

        nodeEnv: 'test'
      });

    const result =
      await service.deliver(
        notification()
      );

    assert.equal(
      result.failed,
      1
    );

    assert.equal(
      result.removed,
      0
    );

    assert.equal(
      cleanupCalls,
      0
    );
  }
);

test(
  'registry lookup failure is swallowed by the best-effort pipeline',
  async () => {
    const service =
      createPushDeliveryService({
        transportAvailable:
          () => true,

        buildMessage:
          () => message(),

        registrationService: {
          async listDeliveryTargetsForUser() {
            throw Object.assign(
              new Error(
                'contains-private-data'
              ),
              {
                name:
                  'MongoServerError',
                code: 91
              }
            );
          }
        },

        nodeEnv: 'test'
      });

    const result =
      await service.deliver(
        notification()
      );

    assert.equal(
      result.reason,
      'registry-error'
    );

    assert.equal(
      result.sent,
      0
    );
  }
);

test(
  'cleanup failure cannot reject successful notification persistence',
  async () => {
    const service =
      createPushDeliveryService({
        transportAvailable:
          () => true,

        buildMessage:
          () => message(),

        registrationService: {
          async listDeliveryTargetsForUser() {
            return [
              {
                _id: 'r1',
                targetKind: 'fid',
                target:
                  'dead-fid-123456789',
                platform: 'ios'
              }
            ];
          },

          async removeDeliveryTarget() {
            throw new Error(
              'database private detail'
            );
          }
        },

        async sendTarget() {
          return {
            sent: false,
            reason:
              'provider-error',
            terminal: true,
            error:
              Object.assign(
                new Error('gone'),
                {
                  code:
                    'messaging/registration-token-not-registered'
                }
              )
          };
        },

        nodeEnv: 'test'
      });

    const result =
      await service.deliver(
        notification()
      );

    assert.equal(
      result.failed,
      1
    );

    assert.equal(
      result.removed,
      0
    );
  }
);

test(
  'unexpected pipeline exception is converted to a safe result',
  async () => {
    const service =
      createPushDeliveryService({
        transportAvailable:
          () => true,

        buildMessage() {
          throw new Error(
            'private-notification-content'
          );
        },

        nodeEnv: 'test'
      });

    const result =
      await service.deliver(
        notification()
      );

    assert.equal(
      result.reason,
      'pipeline-error'
    );
  }
);

test(
  'all delivery diagnostics omit targets, content and raw error messages',
  () => {
    const secret =
      'PRIVATE-TOKEN-AND-MESSAGE';

    const error =
      new Error(secret);

    error.name =
      'MongoServerError';

    error.code = 91;

    const logs = [
      pushRegistryLookupFailureLog(
        'newMessage',
        error
      ),
      pushTargetCleanupFailureLog(
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
      ),
      pushPipelineFailureLog(
        'newMessage',
        error
      )
    ];

    for (const parts of logs) {
      const line =
        parts.join(' ');

      assert.equal(
        line.includes(secret),
        false
      );

      assert.equal(
        line.includes(
          'PRIVATE'
        ),
        false
      );
    }
  }
);

test(
  'notification service hooks push only after successful MongoDB create',
  () => {
    const source =
      fs.readFileSync(
        new URL(
          '../src/services/notification.service.js',
          import.meta.url
        ),
        'utf8'
      );

    const createIndex =
      source.indexOf(
        'await Notification.create(payload)'
      );

    const realtimeIndex =
      source.indexOf(
        'publishNotificationsChanged({'
      );

    const pushIndex =
      source.indexOf(
        'void deliverNotificationPush(notification)'
      );

    const returnIndex =
      source.indexOf(
        'return notification;',
        createIndex
      );

    assert.ok(
      createIndex >= 0
    );

    assert.ok(
      realtimeIndex > createIndex
    );

    assert.ok(
      pushIndex > realtimeIndex
    );

    assert.ok(
      returnIndex > pushIndex
    );
  }
);
