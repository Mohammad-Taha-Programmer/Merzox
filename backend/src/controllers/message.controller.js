import mongoose from 'mongoose';

import { Business } from '../models/Business.js';
import { Conversation } from '../models/Conversation.js';
import { Message } from '../models/Message.js';
import { notifyNewMessage } from '../services/notification.service.js';
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

function conversationFilter(query) {
  const filter = String(query.filter ?? 'all').trim();

  if (filter !== 'all' && filter !== 'unread') {
    throw new AppError(
      'Conversation filter must be all or unread',
      400,
      'INVALID_CONVERSATION_FILTER'
    );
  }

  return filter;
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
    if (business && conversation.business.equals(business._id)) {
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

  const conversation = await Conversation.findOneAndUpdate(
    { user: req.user._id, business: business._id },
    {
      $setOnInsert: {
        user: req.user._id,
        business: business._id
      },
      $set: {
        userName: req.user.name,
        businessName: business.name,
        businessLogoUrl: business.logoUrl ?? '',
        isActive: true
      }
    },
    { new: true, upsert: true, setDefaultsOnInsert: true }
  );

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

  const message = await Message.create({
    conversation: conversation._id,
    business: conversation.business,
    user: conversation.user,
    senderType: viewerType,
    senderName,
    body
  });

  const unreadField =
    viewerType === 'customer' ? 'unreadForBusiness' : 'unreadForUser';

  const updated = await Conversation.findByIdAndUpdate(
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

  if (viewerType === 'customer') {
    const owner = business?.owner ?? (await Business.findById(conversation.business))?.owner;
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

  const [updated] = await Promise.all([
    Conversation.findByIdAndUpdate(
      conversation._id,
      { $set: { [unreadField]: 0 } },
      { new: true }
    ),
    Message.updateMany(
      {
        conversation: conversation._id,
        senderType: counterpart,
        readAt: null
      },
      { $set: { readAt: new Date() } }
    )
  ]);

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
