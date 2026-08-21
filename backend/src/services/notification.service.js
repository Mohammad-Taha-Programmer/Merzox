import { Notification } from '../models/Notification.js';

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
async function create(payload) {
  try {
    const notification = await Notification.create(payload);
    return notification;
  } catch {
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
