export const realtimeEvents = Object.freeze({
  messagesChanged: 'merzox:messages-changed',
  notificationsChanged: 'merzox:notifications-changed'
});

let realtimeEmitter = null;

export function registerRealtimeEmitter(emitter) {
  if (typeof emitter !== 'function') {
    throw new TypeError(
      'Realtime emitter must be a function'
    );
  }

  realtimeEmitter = emitter;

  return function unregisterRealtimeEmitter() {
    if (realtimeEmitter === emitter) {
      realtimeEmitter = null;
    }
  };
}

function normalizedId(value) {
  return String(value ?? '').trim();
}

export function publishMessagesChanged({
  recipientIds,
  conversationId,
  businessId,
  messageId,
  reason
}) {
  const emitter = realtimeEmitter;

  if (!emitter) {
    return false;
  }

  const normalizedConversationId =
    normalizedId(conversationId);

  const normalizedBusinessId =
    normalizedId(businessId);

  const normalizedMessageId =
    normalizedId(messageId);

  const normalizedReason =
    normalizedId(reason);

  if (
    !normalizedConversationId ||
    !normalizedBusinessId ||
    !normalizedReason
  ) {
    return false;
  }

  const recipients = [
    ...new Set(
      (recipientIds ?? [])
        .map(normalizedId)
        .filter(Boolean)
    )
  ];

  if (recipients.length === 0) {
    return false;
  }

  const payload = {
    conversationId: normalizedConversationId,
    businessId: normalizedBusinessId,
    reason: normalizedReason,
    ...(normalizedMessageId
      ? { messageId: normalizedMessageId }
      : {})
  };

  let published = false;

  for (const recipientId of recipients) {
    try {
      emitter(
        recipientId,
        realtimeEvents.messagesChanged,
        payload
      );

      published = true;
    } catch (_) {
      // Realtime is an invalidation channel, never the authoritative write.
      // A socket delivery failure must not turn a persisted REST mutation into
      // a failed request.
    }
  }

  return published;
}

export function publishNotificationsChanged({
  recipientIds,
  audience,
  notificationId,
  businessId,
  reason
}) {
  const emitter = realtimeEmitter;

  if (!emitter) {
    return false;
  }

  const normalizedAudience =
    normalizedId(audience);

  const normalizedNotificationId =
    normalizedId(notificationId);

  const normalizedBusinessId =
    normalizedId(businessId);

  const normalizedReason =
    normalizedId(reason);

  if (
    normalizedAudience !== 'customer' &&
    normalizedAudience !== 'business'
  ) {
    return false;
  }

  if (
    normalizedReason !== 'notification-created' &&
    normalizedReason !== 'notification-read' &&
    normalizedReason !== 'notifications-read-all'
  ) {
    return false;
  }

  if (
    (
      normalizedReason === 'notification-created' ||
      normalizedReason === 'notification-read'
    ) &&
    !normalizedNotificationId
  ) {
    return false;
  }

  const recipients = [
    ...new Set(
      (recipientIds ?? [])
        .map(normalizedId)
        .filter(Boolean)
    )
  ];

  if (recipients.length === 0) {
    return false;
  }

  const payload = {
    audience: normalizedAudience,
    reason: normalizedReason,
    ...(normalizedNotificationId
      ? { notificationId: normalizedNotificationId }
      : {}),
    ...(normalizedBusinessId
      ? { businessId: normalizedBusinessId }
      : {})
  };

  let published = false;

  for (const recipientId of recipients) {
    try {
      emitter(
        recipientId,
        realtimeEvents.notificationsChanged,
        payload
      );

      published = true;
    } catch (_) {
      // Notifications are persisted REST/MongoDB truth. Socket delivery is
      // only an invalidation hint and must never roll back a successful write.
    }
  }

  return published;
}
