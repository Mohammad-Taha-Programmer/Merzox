import mongoose from 'mongoose';

import { logger } from '../observability/logger.js';
import {
  safeErrorCode,
  safeErrorName
} from '../utils/safe-log.js';

import { Business } from '../models/Business.js';
import { paginationParams, readFilterParam } from '../policies/query.policy.js';
import { Conversation } from '../models/Conversation.js';
import { Message } from '../models/Message.js';
import {
  resolveSendFailure
} from '../policies/message-consistency.policy.js';
import {
  acknowledgementFilter,
  acknowledgementUpdate,
  isNoOpAcknowledgement
} from '../policies/unread-counter.policy.js';
import { publishMessagesChanged } from '../realtime/realtime.publisher.js';
import { notifyNewMessage } from '../services/notification.service.js';
import { AppError } from '../utils/AppError.js';
import { asyncHandler } from '../utils/asyncHandler.js';

function conversationFilter(query) {
  return readFilterParam(query.filter, 'INVALID_CONVERSATION_FILTER');
}

function findBusiness(id) {
  if (/^[a-f\d]{24}$/i.test(id)) {
    return Business.findById(id);
  }

  return Business.findOne({ publicId: id });
}

async function requireOwnedBusiness(req) {
  const business = await Business.findOne({ owner: req.user._id });

  if (!business) {
    throw new AppError(
      'Business profile was not found',
      404,
      'BUSINESS_PROFILE_NOT_FOUND'
    );
  }

  if (!business.isActive) {
    throw new AppError(
      'Business account is disabled',
      403,
      'BUSINESS_ACCOUNT_DISABLED'
    );
  }

  return business;
}

/**
 * Removes a message whose conversation summary could not be updated.
 *
 * Returns whether the compensation actually succeeded. When it did not, the
 * caller must not report the original cause: a message now exists that no
 * conversation summary accounts for, and only a distinct error conveys that.
 */
async function compensateMessage(messageId) {
  try {
    await Message.deleteOne({ _id: messageId });
    return true;
  } catch (error) {
    logger.error(
      'message_compensation_failed',
      {
        appCode:
          'MESSAGE_COMPENSATION_FAILED',
        errorName:
          safeErrorName(error),
        errorCode:
          safeErrorCode(error)
      }
    );
    return false;
  }
}

async function loadConversation(id) {
  if (!mongoose.isValidObjectId(id)) {
    throw new AppError('Conversation id is invalid', 400, 'INVALID_CONVERSATION_ID');
  }

  const conversation = await Conversation.findById(id);

  if (!conversation || !conversation.isActive) {
    throw new AppError('Conversation was not found', 404, 'CONVERSATION_NOT_FOUND');
  }

  return conversation;
}

/**
 * Resolves the side the caller is speaking from. A customer owns the
 * conversation through `user`; a merchant owns it through the business they
 * registered. Anyone else is refused before a single message is read.
 */
async function resolveViewer(req, conversation) {
  if (conversation.user.equals(req.user._id)) {
    return { viewerType: 'customer', business: null };
  }

  if (req.user.userType === 'business') {
    const business = await Business.findOne({ owner: req.user._id });
    // isActive is checked here too, so a disabled store cannot keep reading or
    // answering threads through the per-conversation routes after the list
    // routes have already started refusing it.
    if (business && business.isActive && conversation.business.equals(business._id)) {
      return { viewerType: 'business', business };
    }
  }

  throw new AppError('Conversation was not found', 404, 'CONVERSATION_NOT_FOUND');
}

async function listConversationsFor(res, { filter, query, baseFilter, mapper, unreadField }) {
  const { page, limit, skip } = paginationParams(query);
  const criteria = { ...baseFilter, isActive: true };

  if (filter === 'unread') {
    criteria[unreadField] = { $gt: 0 };
  }

  const [conversations, total, unreadTotal] = await Promise.all([
    Conversation.find(criteria)
      .sort({ updatedAt: -1, _id: -1 })
      .skip(skip)
      .limit(limit),
    Conversation.countDocuments(criteria),
    Conversation.countDocuments({
      ...baseFilter,
      isActive: true,
      [unreadField]: { $gt: 0 }
    })
  ]);

  res.json({
    success: true,
    data: {
      conversations: conversations.map(mapper),
      unreadConversationCount: unreadTotal,
      pagination: { page, limit, total, hasMore: skip + conversations.length < total }
    }
  });
}

export const listMyConversations = asyncHandler(async (req, res) => {
  await listConversationsFor(res, {
    filter: conversationFilter(req.query),
    query: req.query,
    baseFilter: { user: req.user._id },
    mapper: (conversation) => conversation.toCustomerJSON(),
    unreadField: 'unreadForUser'
  });
});

export const listMerchantConversations = asyncHandler(async (req, res) => {
  const business = await requireOwnedBusiness(req);

  await listConversationsFor(res, {
    filter: conversationFilter(req.query),
    query: req.query,
    baseFilter: { business: business._id },
    mapper: (conversation) => conversation.toMerchantJSON(),
    unreadField: 'unreadForBusiness'
  });
});

export const openConversation = asyncHandler(async (req, res) => {
  const businessId = String(req.body.businessId ?? '').trim();
  const business = await findBusiness(businessId);

  if (!business || !business.isActive) {
    throw new AppError('Business not found', 404, 'BUSINESS_NOT_FOUND');
  }

  if (business.owner && business.owner.equals(req.user._id)) {
    throw new AppError(
      'A business cannot start a conversation with itself',
      400,
      'INVALID_CONVERSATION_TARGET'
    );
  }

  const filter = { user: req.user._id, business: business._id };
  const update = {
    $setOnInsert: { user: req.user._id, business: business._id },
    $set: {
      userName: req.user.name,
      businessName: business.name,
      businessLogoUrl: business.logoUrl ?? '',
      isActive: true
    }
  };

  let conversation;
  try {
    conversation = await Conversation.findOneAndUpdate(filter, update, {
      new: true,
      upsert: true,
      setDefaultsOnInsert: true
    });
  } catch (error) {
    // Two simultaneous "open chat" taps both miss the document and both try to
    // insert. The unique {user, business} index lets exactly one win; the loser
    // reads the winner's row instead of surfacing a duplicate-key error.
    if (error?.code !== 11000) throw error;

    conversation = await Conversation.findOne(filter);
    if (!conversation) throw error;
  }

  res.status(201).json({
    success: true,
    data: { conversation: conversation.toCustomerJSON() }
  });
});

export const listConversationMessages = asyncHandler(async (req, res) => {
  const conversation = await loadConversation(req.params.id);
  const { viewerType } = await resolveViewer(req, conversation);
  const { page, limit, skip } = paginationParams(req.query);

  const [messages, total] = await Promise.all([
    Message.find({ conversation: conversation._id })
      .sort({ createdAt: -1, _id: -1 })
      .skip(skip)
      .limit(limit),
    Message.countDocuments({ conversation: conversation._id })
  ]);

  res.json({
    success: true,
    data: {
      conversation:
        viewerType === 'customer'
          ? conversation.toCustomerJSON()
          : conversation.toMerchantJSON(),
      // Newest first on the wire so paging back through history is a simple
      // skip; the client renders them oldest first.
      messages: messages.map((message) => message.toClientJSON(viewerType)),
      pagination: { page, limit, total, hasMore: skip + messages.length < total }
    }
  });
});

export const sendConversationMessage = asyncHandler(async (req, res) => {
  const conversation = await loadConversation(req.params.id);
  const { viewerType, business } = await resolveViewer(req, conversation);
  const body = String(req.body.body ?? '').trim();

  const senderName =
    viewerType === 'customer'
      ? req.user.name
      : business?.name ?? conversation.businessName;

  const unreadField =
    viewerType === 'customer' ? 'unreadForBusiness' : 'unreadForUser';

  // The message and the conversation summary are two documents. Transactions
  // are deliberately not used: the deployment topology is not guaranteed to be
  // a replica set, and a standalone MongoDB would reject them outright.
  // Instead the write is compensated - if the summary update fails, the
  // just-created message is removed and the request fails, so a 201 always
  // means both documents agree.
  const message = await Message.create({
    conversation: conversation._id,
    business: conversation.business,
    user: conversation.user,
    senderType: viewerType,
    senderName,
    body
  });

  let updated;
  try {
    updated = await Conversation.findByIdAndUpdate(
      conversation._id,
      {
        $set: {
          lastMessage: {
            body: message.body,
            senderType: viewerType,
            sentAt: message.createdAt
          }
        },
        $inc: { [unreadField]: 1, messageCount: 1 }
      },
      { new: true }
    );
  } catch (error) {
    const compensated = await compensateMessage(message._id);
    throw resolveSendFailure({ compensated, originalError: error });
  }

  // A null result means the conversation disappeared between the access check
  // and this write; the orphaned message must not survive it.
  if (!updated) {
    const compensated = await compensateMessage(message._id);
    throw resolveSendFailure({ compensated });
  }

  let counterpartUserId = conversation.user;

  if (viewerType === 'customer') {
    const owner =
      business?.owner ??
      (await Business.findById(conversation.business))?.owner;

    counterpartUserId = owner ?? null;

    if (owner) {
      await notifyNewMessage({
        recipientId: owner,
        audience: 'business',
        businessId: conversation.business,
        conversationId: conversation._id.toString(),
        senderName,
        body: message.body
      });
    }
  } else {
    await notifyNewMessage({
      recipientId: conversation.user,
      audience: 'customer',
      businessId: conversation.business,
      conversationId: conversation._id.toString(),
      senderName,
      body: message.body
    });
  }

  publishMessagesChanged({
    recipientIds: [
      req.user._id,
      counterpartUserId
    ],
    conversationId: conversation._id,
    businessId: conversation.business,
    messageId: message._id,
    reason: 'message-created'
  });

  res.status(201).json({
    success: true,
    data: {
      message: message.toClientJSON(viewerType),
      conversation:
        viewerType === 'customer'
          ? updated.toCustomerJSON()
          : updated.toMerchantJSON()
    }
  });
});

export const markConversationRead = asyncHandler(async (req, res) => {
  const conversation = await loadConversation(req.params.id);
  const { viewerType } = await resolveViewer(req, conversation);

  const unreadField =
    viewerType === 'customer' ? 'unreadForUser' : 'unreadForBusiness';
  const counterpart = viewerType === 'customer' ? 'business' : 'customer';

  // A read acknowledgement may only cover what already existed when the
  // request reached the server. Without this cutoff a message that arrives
  // mid-request would be silently consumed as "read" by an acknowledgement the
  // reader never saw.
  const readThrough = new Date();

  // Messages are settled first, then the counter is adjusted by exactly what
  // that update changed. The counter is never recomputed and re-set: a recount
  // would overwrite an increment a sender made in between, leaving an unread
  // message behind a zeroed badge.
  const acknowledgement = await Message.updateMany(
    acknowledgementFilter({
      conversationId: conversation._id,
      counterpartSenderType: counterpart,
      readThrough
    }),
    { $set: { readAt: readThrough } }
  );

  const acknowledged = acknowledgement.modifiedCount ?? 0;

  // Nothing was acknowledged, so the counter must not be touched at all - a
  // concurrent sender's increment has to survive an empty acknowledgement.
  let updated;
  if (isNoOpAcknowledgement(acknowledged)) {
    updated = await Conversation.findById(conversation._id);
  } else {
    await Conversation.updateOne(
      { _id: conversation._id },
      acknowledgementUpdate(unreadField, acknowledged)
    );
    updated = await Conversation.findById(conversation._id);
  }

  if (!updated) {
    throw new AppError(
      'Conversation was not found',
      404,
      'CONVERSATION_NOT_FOUND'
    );
  }

  publishMessagesChanged({
    recipientIds: [req.user._id],
    conversationId: conversation._id,
    businessId: conversation.business,
    reason: 'conversation-read'
  });

  res.json({
    success: true,
    data: {
      conversation:
        viewerType === 'customer'
          ? updated.toCustomerJSON()
          : updated.toMerchantJSON()
    }
  });
});

export const getMyConversationUnreadCount = asyncHandler(async (req, res) => {
  const [conversations, messages] = await Promise.all([
    Conversation.countDocuments({
      user: req.user._id,
      isActive: true,
      unreadForUser: { $gt: 0 }
    }),
    Conversation.aggregate([
      { $match: { user: req.user._id, isActive: true } },
      { $group: { _id: null, total: { $sum: '$unreadForUser' } } }
    ])
  ]);

  res.json({
    success: true,
    data: {
      conversationCount: conversations,
      messageCount: messages[0]?.total ?? 0
    }
  });
});

export const getMerchantConversationUnreadCount = asyncHandler(async (req, res) => {
  const business = await requireOwnedBusiness(req);
  const [conversations, messages] = await Promise.all([
    Conversation.countDocuments({
      business: business._id,
      isActive: true,
      unreadForBusiness: { $gt: 0 }
    }),
    Conversation.aggregate([
      { $match: { business: business._id, isActive: true } },
      { $group: { _id: null, total: { $sum: '$unreadForBusiness' } } }
    ])
  ]);

  res.json({
    success: true,
    data: {
      conversationCount: conversations,
      messageCount: messages[0]?.total ?? 0
    }
  });
});
