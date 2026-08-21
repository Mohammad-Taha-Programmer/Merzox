import mongoose from 'mongoose';

import { Notification } from '../models/Notification.js';
import { AppError } from '../utils/AppError.js';
import { asyncHandler } from '../utils/asyncHandler.js';

function paginationParams(query) {
  const parsedPage = Number.parseInt(query.page ?? '1', 10);
  const parsedLimit = Number.parseInt(query.limit ?? '20', 10);
  const page = Number.isFinite(parsedPage) ? Math.max(parsedPage, 1) : 1;
  const limit = Number.isFinite(parsedLimit)
    ? Math.min(Math.max(parsedLimit, 1), 50)
    : 20;

  return { page, limit, skip: (page - 1) * limit };
}

/**
 * A business owner keeps a customer account too, so the audience is taken from
 * the request rather than inferred from the account type.
 */
function audienceFrom(query, user) {
  const requested = String(query.audience ?? 'customer').trim();

  if (requested !== 'customer' && requested !== 'business') {
    throw new AppError(
      'Notification audience must be customer or business',
      400,
      'INVALID_NOTIFICATION_AUDIENCE'
    );
  }

  if (requested === 'business' && user.userType !== 'business') {
    throw new AppError(
      'A business account is required',
      403,
      'BUSINESS_ACCOUNT_REQUIRED'
    );
  }

  return requested;
}

export const listMyNotifications = asyncHandler(async (req, res) => {
  const audience = audienceFrom(req.query, req.user);
  const { page, limit, skip } = paginationParams(req.query);
  const onlyUnread = String(req.query.filter ?? 'all').trim() === 'unread';
  const baseFilter = { user: req.user._id, audience };
  const criteria = onlyUnread ? { ...baseFilter, readAt: null } : baseFilter;

  const [notifications, total, unreadCount] = await Promise.all([
    Notification.find(criteria)
      .sort({ createdAt: -1, _id: -1 })
      .skip(skip)
      .limit(limit),
    Notification.countDocuments(criteria),
    Notification.countDocuments({ ...baseFilter, readAt: null })
  ]);

  res.json({
    success: true,
    data: {
      notifications: notifications.map((notification) =>
        notification.toClientJSON()
      ),
      unreadCount,
      pagination: {
        page,
        limit,
        total,
        hasMore: skip + notifications.length < total
      }
    }
  });
});

export const getMyNotificationUnreadCount = asyncHandler(async (req, res) => {
  const audience = audienceFrom(req.query, req.user);
  const unreadCount = await Notification.countDocuments({
    user: req.user._id,
    audience,
    readAt: null
  });

  res.json({ success: true, data: { unreadCount } });
});

export const markNotificationRead = asyncHandler(async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id)) {
    throw new AppError('Notification id is invalid', 400, 'INVALID_NOTIFICATION_ID');
  }

  const notification = await Notification.findOneAndUpdate(
    { _id: req.params.id, user: req.user._id, readAt: null },
    { $set: { readAt: new Date() } },
    { new: true }
  );

  if (!notification) {
    const existing = await Notification.findOne({
      _id: req.params.id,
      user: req.user._id
    });

    if (!existing) {
      throw new AppError('Notification was not found', 404, 'NOTIFICATION_NOT_FOUND');
    }

    res.json({ success: true, data: { notification: existing.toClientJSON() } });
    return;
  }

  res.json({ success: true, data: { notification: notification.toClientJSON() } });
});

export const markAllNotificationsRead = asyncHandler(async (req, res) => {
  const audience = audienceFrom(req.body, req.user);
  const result = await Notification.updateMany(
    { user: req.user._id, audience, readAt: null },
    { $set: { readAt: new Date() } }
  );

  res.json({
    success: true,
    data: { updatedCount: result.modifiedCount ?? 0, unreadCount: 0 }
  });
});
