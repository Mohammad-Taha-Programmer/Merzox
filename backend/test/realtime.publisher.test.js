import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

import {
  publishMessagesChanged,
  publishNotificationsChanged,
  realtimeEvents,
  registerRealtimeEmitter
} from '../src/realtime/realtime.publisher.js';

test(
  'realtime message event name is stable',
  () => {
    assert.equal(
      realtimeEvents.messagesChanged,
      'merzox:messages-changed'
    );
  }
);

test(
  'publisher is best-effort when no realtime server is registered',
  () => {
    assert.equal(
      publishMessagesChanged({
        recipientIds: ['user-1'],
        conversationId: 'conversation-1',
        businessId: 'business-1',
        messageId: 'message-1',
        reason: 'message-created'
      }),
      false
    );
  }
);

test(
  'message invalidation deduplicates recipients and exposes no message body',
  () => {
    const emissions = [];

    const unregister = registerRealtimeEmitter(
      (userId, event, payload) => {
        emissions.push({
          userId,
          event,
          payload
        });
      }
    );

    try {
      const published =
        publishMessagesChanged({
          recipientIds: [
            'customer-1',
            'business-owner-1',
            'customer-1',
            '',
            null
          ],
          conversationId: 'conversation-1',
          businessId: 'business-1',
          messageId: 'message-1',
          reason: 'message-created'
        });

      assert.equal(published, true);

      assert.deepEqual(
        emissions,
        [
          {
            userId: 'customer-1',
            event: 'merzox:messages-changed',
            payload: {
              conversationId: 'conversation-1',
              businessId: 'business-1',
              reason: 'message-created',
              messageId: 'message-1'
            }
          },
          {
            userId: 'business-owner-1',
            event: 'merzox:messages-changed',
            payload: {
              conversationId: 'conversation-1',
              businessId: 'business-1',
              reason: 'message-created',
              messageId: 'message-1'
            }
          }
        ]
      );

      assert.equal(
        Object.hasOwn(
          emissions[0].payload,
          'body'
        ),
        false
      );

      assert.equal(
        Object.hasOwn(
          emissions[0].payload,
          'senderName'
        ),
        false
      );
    } finally {
      unregister();
    }
  }
);

test(
  'one realtime transport failure cannot fail the authoritative mutation',
  () => {
    const delivered = [];

    const unregister = registerRealtimeEmitter(
      (userId) => {
        if (userId === 'broken-device-user') {
          throw new Error(
            'socket transport failed'
          );
        }

        delivered.push(userId);
      }
    );

    try {
      assert.doesNotThrow(() => {
        publishMessagesChanged({
          recipientIds: [
            'broken-device-user',
            'healthy-user'
          ],
          conversationId: 'conversation-1',
          businessId: 'business-1',
          reason: 'conversation-read'
        });
      });

      assert.deepEqual(
        delivered,
        ['healthy-user']
      );
    } finally {
      unregister();
    }
  }
);

test(
  'message controller publishes only after the consistent send path',
  () => {
    const source = fs.readFileSync(
      new URL(
        '../src/controllers/message.controller.js',
        import.meta.url
      ),
      'utf8'
    );

    const start = source.indexOf(
      'export const sendConversationMessage'
    );

    const end = source.indexOf(
      'export const markConversationRead'
    );

    assert.ok(start >= 0);
    assert.ok(end > start);

    const send = source.slice(start, end);

    const createIndex =
      send.indexOf('Message.create(');

    const summaryIndex =
      send.indexOf(
        'Conversation.findByIdAndUpdate('
      );

    const nullGuardIndex =
      send.indexOf('if (!updated)');

    const publishIndex =
      send.indexOf(
        'publishMessagesChanged({'
      );

    assert.ok(createIndex >= 0);
    assert.ok(summaryIndex > createIndex);
    assert.ok(nullGuardIndex > summaryIndex);
    assert.ok(publishIndex > nullGuardIndex);

    const publishBlock = send.slice(
      publishIndex,
      send.indexOf(
        'res.status(201)',
        publishIndex
      )
    );

    assert.match(
      publishBlock,
      /reason:\s*'message-created'/
    );

    assert.doesNotMatch(
      publishBlock,
      /\bbody\b/
    );

    assert.doesNotMatch(
      publishBlock,
      /\bsenderName\b/
    );
  }
);

test(
  'mark-read invalidation targets the authenticated reader session',
  () => {
    const source = fs.readFileSync(
      new URL(
        '../src/controllers/message.controller.js',
        import.meta.url
      ),
      'utf8'
    );

    const start = source.indexOf(
      'export const markConversationRead'
    );

    const end = source.indexOf(
      'export const getMyConversationUnreadCount'
    );

    assert.ok(start >= 0);
    assert.ok(end > start);

    const markRead = source.slice(
      start,
      end
    );

    assert.match(
      markRead,
      /recipientIds:\s*\[req\.user\._id\]/
    );

    assert.match(
      markRead,
      /reason:\s*'conversation-read'/
    );
  }
);


test(
  'realtime notification event name is stable',
  () => {
    assert.equal(
      realtimeEvents.notificationsChanged,
      'merzox:notifications-changed'
    );
  }
);

test(
  'notification invalidation preserves audience and exposes no content',
  () => {
    const emissions = [];

    const unregister = registerRealtimeEmitter(
      (userId, event, payload) => {
        emissions.push({
          userId,
          event,
          payload
        });
      }
    );

    try {
      const published =
        publishNotificationsChanged({
          recipientIds: [
            'user-1',
            'user-1'
          ],
          audience: 'business',
          notificationId:
            'notification-1',
          businessId:
            'business-1',
          reason:
            'notification-created'
        });

      assert.equal(
        published,
        true
      );

      assert.deepEqual(
        emissions,
        [
          {
            userId: 'user-1',
            event:
              'merzox:notifications-changed',
            payload: {
              audience: 'business',
              reason:
                'notification-created',
              notificationId:
                'notification-1',
              businessId:
                'business-1'
            }
          }
        ]
      );

      assert.equal(
        Object.hasOwn(
          emissions[0].payload,
          'title'
        ),
        false
      );

      assert.equal(
        Object.hasOwn(
          emissions[0].payload,
          'body'
        ),
        false
      );

      assert.equal(
        Object.hasOwn(
          emissions[0].payload,
          'data'
        ),
        false
      );
    } finally {
      unregister();
    }
  }
);

test(
  'notification publisher rejects unknown audience and reason',
  () => {
    const emissions = [];

    const unregister =
      registerRealtimeEmitter(
        (...args) => {
          emissions.push(args);
        }
      );

    try {
      assert.equal(
        publishNotificationsChanged({
          recipientIds: ['user-1'],
          audience: 'admin',
          notificationId: 'n1',
          reason: 'notification-created'
        }),
        false
      );

      assert.equal(
        publishNotificationsChanged({
          recipientIds: ['user-1'],
          audience: 'customer',
          notificationId: 'n1',
          reason: 'unknown-reason'
        }),
        false
      );

      assert.deepEqual(
        emissions,
        []
      );
    } finally {
      unregister();
    }
  }
);

test(
  'notification creation and single-read events require notification id',
  () => {
    const emissions = [];

    const unregister =
      registerRealtimeEmitter(
        (...args) => {
          emissions.push(args);
        }
      );

    try {
      for (const reason of [
        'notification-created',
        'notification-read'
      ]) {
        assert.equal(
          publishNotificationsChanged({
            recipientIds: ['user-1'],
            audience: 'customer',
            reason
          }),
          false
        );
      }

      assert.equal(
        publishNotificationsChanged({
          recipientIds: ['user-1'],
          audience: 'customer',
          reason:
            'notifications-read-all'
        }),
        true
      );

      assert.equal(
        emissions.length,
        1
      );
    } finally {
      unregister();
    }
  }
);

test(
  'notification transport failure stays best-effort',
  () => {
    const delivered = [];

    const unregister =
      registerRealtimeEmitter(
        (userId) => {
          if (userId === 'broken-user') {
            throw new Error(
              'transport unavailable'
            );
          }

          delivered.push(userId);
        }
      );

    try {
      assert.doesNotThrow(() => {
        publishNotificationsChanged({
          recipientIds: [
            'broken-user',
            'healthy-user'
          ],
          audience: 'customer',
          notificationId: 'n1',
          reason:
            'notification-created'
        });
      });

      assert.deepEqual(
        delivered,
        ['healthy-user']
      );
    } finally {
      unregister();
    }
  }
);

test(
  'notification service publishes only after MongoDB persistence succeeds',
  () => {
    const source = fs.readFileSync(
      new URL(
        '../src/services/notification.service.js',
        import.meta.url
      ),
      'utf8'
    );

    const createStart =
      source.indexOf(
        'async function create(payload)'
      );

    const createEnd =
      source.indexOf(
        'export function notifyOrderPlaced'
      );

    assert.ok(createStart >= 0);
    assert.ok(createEnd > createStart);

    const createSource =
      source.slice(
        createStart,
        createEnd
      );

    const persistIndex =
      createSource.indexOf(
        'await Notification.create(payload)'
      );

    const publishIndex =
      createSource.indexOf(
        'publishNotificationsChanged({'
      );

    const returnIndex =
      createSource.indexOf(
        'return notification'
      );

    assert.ok(
      persistIndex >= 0
    );

    assert.ok(
      publishIndex > persistIndex
    );

    assert.ok(
      returnIndex > publishIndex
    );

    assert.match(
      createSource,
      /reason:\s*'notification-created'/
    );
  }
);

test(
  'notification read-state publications happen only after successful writes',
  () => {
    const source = fs.readFileSync(
      new URL(
        '../src/controllers/notification.controller.js',
        import.meta.url
      ),
      'utf8'
    );

    const singleStart =
      source.indexOf(
        'export const markNotificationRead'
      );

    const bulkStart =
      source.indexOf(
        'export const markAllNotificationsRead'
      );

    assert.ok(singleStart >= 0);
    assert.ok(bulkStart > singleStart);

    const single =
      source.slice(
        singleStart,
        bulkStart
      );

    assert.ok(
      single.indexOf(
        'Notification.findOneAndUpdate('
      ) >= 0
    );

    assert.ok(
      single.indexOf(
        'publishNotificationsChanged({'
      ) >
      single.indexOf(
        'if (!notification)'
      )
    );

    assert.match(
      single,
      /reason:\s*'notification-read'/
    );

    const bulk =
      source.slice(bulkStart);

    assert.ok(
      bulk.indexOf(
        'Notification.updateMany('
      ) >= 0
    );

    assert.ok(
      bulk.indexOf(
        'publishNotificationsChanged({'
      ) >
      bulk.indexOf(
        'const updatedCount'
      )
    );

    assert.match(
      bulk,
      /if \(updatedCount > 0\)/
    );

    assert.match(
      bulk,
      /reason:\s*'notifications-read-all'/
    );
  }
);
