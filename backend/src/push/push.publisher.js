import {
  notificationTypes
} from '../models/Notification.js';
import {
  formatErrorCode,
  safeErrorName
} from '../utils/safe-log.js';

const PUSH_TARGET_KINDS =
  new Set(['token', 'fid']);

const PUSH_TERMINAL_ERROR_CODES =
  new Set([
    'messaging/registration-token-not-registered',
    'messaging/invalid-registration-token'
  ]);

let pushSender = null;

function normalizedId(value) {
  return String(value ?? '').trim();
}

function boundedText(
  value,
  maxLength
) {
  const text =
    typeof value === 'string'
      ? value.trim()
      : '';

  return text.slice(
    0,
    maxLength
  );
}

function safeAudience(value) {
  return value === 'business'
    ? 'business'
    : value === 'customer'
      ? 'customer'
      : null;
}

function safeType(value) {
  return notificationTypes.includes(value)
    ? value
    : null;
}

function routeMetadata(notification) {
  const result = {};

  const businessId =
    normalizedId(
      notification?.business
    );

  const orderId =
    normalizedId(
      notification?.data?.orderId
    );

  const conversationId =
    normalizedId(
      notification?.data
        ?.conversationId
    );

  if (businessId) {
    result.businessId =
      businessId;
  }

  if (conversationId) {
    result.routeKind =
      'conversation';

    result.conversationId =
      conversationId;

    return result;
  }

  if (orderId) {
    result.routeKind =
      'order';

    result.orderId =
      orderId;

    return result;
  }

  result.routeKind =
    'notifications';

  return result;
}

/**
 * Builds only the data required to open the authoritative REST-backed screen.
 *
 * Order totals, public IDs, sender names, review details and other model data
 * are intentionally not copied into the FCM data payload.
 */
export function buildPushMessage(
  notification
) {
  const notificationId =
    normalizedId(
      notification?._id
    );

  const audience =
    safeAudience(
      notification?.audience
    );

  const type =
    safeType(
      notification?.type
    );

  const title =
    boundedText(
      notification?.title,
      160
    );

  const body =
    boundedText(
      notification?.body,
      640
    );

  if (
    !notificationId ||
    !audience ||
    !type ||
    !title ||
    !body
  ) {
    return null;
  }

  return {
    notification: {
      title,
      body
    },
    data: {
      notificationId,
      audience,
      type,
      ...routeMetadata(
        notification
      )
    }
  };
}

export function registerPushSender(
  sender
) {
  if (typeof sender !== 'function') {
    throw new TypeError(
      'Push sender must be a function'
    );
  }

  pushSender = sender;

  return function unregisterPushSender() {
    if (pushSender === sender) {
      pushSender = null;
    }
  };
}

export function isPushTransportAvailable() {
  return typeof pushSender === 'function';
}

export function isTerminalPushTargetError(
  error
) {
  return PUSH_TERMINAL_ERROR_CODES
    .has(error?.code);
}

export function pushDeliveryFailureLog(
  {
    notificationType,
    targetKind,
    platform
  },
  error
) {
  const safeNotificationType =
    notificationTypes.includes(
      notificationType
    )
      ? notificationType
      : 'unknown';

  const safeTargetKind =
    PUSH_TARGET_KINDS.has(
      targetKind
    )
      ? targetKind
      : 'unknown';

  const safePlatform =
    platform === 'android' ||
    platform === 'ios'
      ? platform
      : 'unknown';

  return [
    '[push] PUSH_DELIVERY_FAILED',
    `type=${safeNotificationType}`,
    `targetKind=${safeTargetKind}`,
    `platform=${safePlatform}`,
    `errorName=${safeErrorName(error)}`,
    `errorCode=${formatErrorCode(error)}`
  ];
}

export function firebasePushInitFailureLog(
  error
) {
  return [
    '[push] FIREBASE_INIT_FAILED',
    `errorName=${safeErrorName(error)}`,
    `errorCode=${formatErrorCode(error)}`
  ];
}

/**
 * Server-internal transport call.
 *
 * No caller may assume delivery success is authoritative. REST/MongoDB remains
 * notification truth.
 */
export async function sendPushTarget({
  targetKind,
  target,
  message
}) {
  const sender = pushSender;

  if (!sender) {
    return {
      sent: false,
      reason: 'disabled'
    };
  }

  if (
    !PUSH_TARGET_KINDS.has(
      targetKind
    ) ||
    typeof target !== 'string' ||
    !target ||
    !message
  ) {
    return {
      sent: false,
      reason: 'invalid-input'
    };
  }

  try {
    const messageId =
      await sender({
        targetKind,
        target,
        message
      });

    return {
      sent: true,
      messageId:
        String(messageId ?? '')
    };
  } catch (error) {
    return {
      sent: false,
      reason:
        'provider-error',
      terminal:
        isTerminalPushTargetError(
          error
        ),
      error
    };
  }
}
