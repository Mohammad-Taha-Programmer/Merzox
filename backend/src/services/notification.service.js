import { env } from '../config/env.js';
import { Notification, notificationTypes } from '../models/Notification.js';
import { deliverNotificationPush } from '../push/push.delivery.js';
import { publishNotificationsChanged } from '../realtime/realtime.publisher.js';
import { formatErrorCode, safeErrorCode, safeErrorName } from '../utils/safe-log.js';

const orderStatusCopy = {
  pending: 'تم الطلب بنجاح',
  confirmed: 'تم وصول طلبك للمتجر',
  preparing: 'يتم تحضير طلبك',
  outForDelivery: 'طلبك في الطريق',
  delivered: 'تم توصيل طلبك',
  cancelled: 'تم إلغاء الطلب'
};

export function orderStatusLabel(status) {
  return orderStatusCopy[status] ?? status;
}

/**
 * Notifications are best-effort: a delivery failure must never fail the request
 * that triggered it, so every write is guarded here rather than at each caller.
 */
/**
 * Reduces a notification type to a value known to the schema. An unrecognised
 * type is reported as 'unknown' rather than echoed, so nothing derived from a
 * request can reach the log through this field.
 */
function safeType(type) {
  return notificationTypes.includes(type) ? type : 'unknown';
}

export function notificationFailureLog(payload, error) {
  return [
    '[notification] NOTIFICATION_PERSIST_FAILED',
    `type=${safeType(payload?.type)}`,
    `errorName=${safeErrorName(error)}`,
    `errorCode=${formatErrorCode(error)}`
  ];
}

async function create(payload) {
  try {
    const notification = await Notification.create(payload);

    publishNotificationsChanged({
      recipientIds: [notification.user],
      audience: notification.audience,
      notificationId: notification._id,
      businessId: notification.business,
      reason: 'notification-created'
    });

    // Push is an attention channel only. It runs after MongoDB has
    // accepted the notification and never controls REST truth.
    void deliverNotificationPush(notification);

    return notification;
  } catch (error) {
    // Best-effort delivery still has to leave a trace, but the trace is built
    // from a fixed allowlist of bounded primitives. The payload carries
    // customer names and order identifiers and is never touched.
    if (env.nodeEnv !== 'test') {
      console.error(...notificationFailureLog(payload, error));
    }
    return null;
  }
}

export function notifyOrderPlaced({ ownerId, businessId, order }) {
  return create({
    user: ownerId,
    audience: 'business',
    business: businessId,
    type: 'orderPlaced',
    title: 'طلب جديد',
    body: `يوجد لديك طلب جديد رقم ${order.publicId}`,
    data: {
      orderId: order._id.toString(),
      publicId: order.publicId,
      total: order.total
    }
  });
}

export function notifyOrderStatus({ userId, order, status }) {
  return create({
    user: userId,
    audience: 'customer',
    business: order.business,
    type: status === 'cancelled' ? 'orderCancelled' : 'orderStatus',
    title: orderStatusLabel(status),
    body: `طلبك رقم ${order.publicId} - ${orderStatusLabel(status)}`,
    data: {
      orderId: order._id.toString(),
      publicId: order.publicId,
      status
    }
  });
}

export function notifyOrderCancelledByCustomer({ ownerId, businessId, order }) {
  return create({
    user: ownerId,
    audience: 'business',
    business: businessId,
    type: 'orderCancelled',
    title: 'تم إلغاء طلب',
    body: `تم إلغاء الطلب رقم ${order.publicId} من قبل العميل`,
    data: {
      orderId: order._id.toString(),
      publicId: order.publicId,
      status: 'cancelled'
    }
  });
}

export function notifyNewMessage({
  recipientId,
  audience,
  businessId,
  conversationId,
  senderName,
  body
}) {
  return create({
    user: recipientId,
    audience,
    business: businessId,
    type: 'newMessage',
    title: senderName || 'رسالة جديدة',
    body,
    data: { conversationId, senderName }
  });
}

export function notifyNewReview({
  ownerId,
  businessId,
  reviewerName,
  rating,
  target
}) {
  const subject = target === 'product' ? 'المنتج' : 'المتجر';
  return create({
    user: ownerId,
    audience: 'business',
    business: businessId,
    type: 'newReview',
    title: 'تقييم جديد',
    body: `قامت ${reviewerName} بتقييم ${subject}`,
    data: { rating, reviewerName, target }
  });
}

/**
 * Exported for testing: these are the only values the failure log may contain.
 */
export const notificationLogSanitizers = {
  safeType,
  safeErrorName,
  safeErrorCode
};
