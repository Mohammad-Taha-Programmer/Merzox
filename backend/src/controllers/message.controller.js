import mongoose from 'mongoose';

import { logger } from '../observability/logger.js';
import {
  safeErrorCode,
  safeErrorName
} from '../utils/safe-log.js';

import { Business } from '../models/Business.js';
import {
  MAX_MESSAGE_HITS,
  MAX_PEOPLE_RESULTS,
  groupMessageHits,
  normalizeSearchQuery,
  searchPattern
} from '../policies/message-search.policy.js';
import {
  counterpartSenderType,
  lastReceivedByConversation,
  lastReceivedPipeline
} from '../policies/conversation-stamp.policy.js';
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
import {
  findShareableProduct,
  readSharedProductId,
  sharedProductSnapshot
} from '../policies/shared-product.policy.js';
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

async function listConversationsFor(
  res,
  { filter, query, baseFilter, mapper, unreadField, viewerType }
) {
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

  // When the other side last wrote, for this page only: the row's stamp is
  // about how long someone has been waiting, not about when the thread last
  // moved, and answering someone moves the thread.
  const received = lastReceivedByConversation(
    await Message.aggregate(
      lastReceivedPipeline(
        conversations.map((conversation) => conversation._id),
        counterpartSenderType(viewerType)
      )
    )
  );

  res.json({
    success: true,
    data: {
      conversations: conversations.map((conversation) =>
        mapper(conversation, {
          lastReceivedAt: received.get(conversation._id.toString()) ?? null
        })
      ),
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
    mapper: (conversation, stamps) => conversation.toCustomerJSON(stamps),
    unreadField: 'unreadForUser',
    viewerType: 'customer'
  });
});

export const listMerchantConversations = asyncHandler(async (req, res) => {
  const business = await requireOwnedBusiness(req);

  await listConversationsFor(res, {
    filter: conversationFilter(req.query),
    query: req.query,
    baseFilter: { business: business._id },
    mapper: (conversation, stamps) => conversation.toMerchantJSON(stamps),
    unreadField: 'unreadForBusiness',
    viewerType: 'business'
  });
});

/**
 * Answers both halves of one typed query.
 *
 * `people` are threads whose other side is named like the query; `messages`
 * are threads where something like the query was said, one row each, opening
 * at the first time it was said.
 *
 * The two are kept apart on the wire rather than merged and ranked. A reader
 * who typed a name wants the thread; a reader who typed a phrase wants the
 * place - and no ranking can tell those apart from the letters alone.
 */
async function searchConversationsFor(res, { query, baseFilter, nameField, mapper }) {
  if (!query) {
    res.json({ success: true, data: { query: '', people: [], messages: [] } });
    return;
  }

  const pattern = searchPattern(query);
  const criteria = { ...baseFilter, isActive: true };

  const [people, mine] = await Promise.all([
    Conversation.find({ ...criteria, [nameField]: pattern })
      .sort({ updatedAt: -1, _id: -1 })
      .limit(MAX_PEOPLE_RESULTS),
    // Scoped to the caller's own threads before a single body is read, so the
    // search can never reach a conversation they are not part of.
    Conversation.find(criteria).select({ _id: 1 })
  ]);

  const hits = await Message.find({
    conversation: { $in: mine.map((conversation) => conversation._id) },
    body: pattern
  })
    .sort({ createdAt: 1, _id: 1 })
    .limit(MAX_MESSAGE_HITS);

  const grouped = groupMessageHits(hits);
  const threads = await Conversation.find({
    _id: { $in: grouped.map((group) => group.conversationId) }
  });
  const byId = new Map(
    threads.map((conversation) => [conversation._id.toString(), conversation])
  );

  res.json({
    success: true,
    data: {
      query,
      people: people.map(mapper),
      messages: grouped
        .filter((group) => byId.has(group.conversationId))
        .map((group) => ({
          conversation: mapper(byId.get(group.conversationId)),
          matchCount: group.matchCount,
          matchIds: group.matchIds,
          snippet: group.snippet,
          sentAt: group.firstMatchAt
        }))
    }
  });
}

export const searchMyConversations = asyncHandler(async (req, res) => {
  await searchConversationsFor(res, {
    query: normalizeSearchQuery(req.query.q ?? req.query.query),
    baseFilter: { user: req.user._id },
    nameField: 'businessName',
    mapper: (conversation) => conversation.toCustomerJSON()
  });
});

export const searchMerchantConversations = asyncHandler(async (req, res) => {
  const business = await requireOwnedBusiness(req);

  await searchConversationsFor(res, {
    query: normalizeSearchQuery(req.query.q ?? req.query.query),
    baseFilter: { business: business._id },
    nameField: 'userName',
    mapper: (conversation) => conversation.toMerchantJSON()
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
      userAvatarUrl: req.user.avatarUrl ?? '',
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

/**
 * The products either side of a conversation may share into it.
 *
 * The shop is the conversation's, never the caller's choice, which is what
 * keeps a merchant to their own shelves and a customer to the shop they are
 * actually talking to. Withdrawn products are left out: a card leading to a
 * page that cannot be opened would be worse than no card.
 */
export const listShareableProducts = asyncHandler(async (req, res) => {
  const conversation = await loadConversation(req.params.id);
  await resolveViewer(req, conversation);

  const business = await Business.findById(conversation.business);

  if (!business || !business.isActive) {
    throw new AppError('Business not found', 404, 'BUSINESS_NOT_FOUND');
  }

  const products = business.products
    .filter((product) => product.isActive)
    .map((product) => business.productToJSON(product));

  res.json({ success: true, data: { products } });
});

export const sendConversationMessage = asyncHandler(async (req, res) => {
  const conversation = await loadConversation(req.params.id);
  const { viewerType, business } = await resolveViewer(req, conversation);
  const body = String(req.body.body ?? '').trim();
  const sharedProductId = readSharedProductId(req.body);

  let sharedProduct = null;
  if (sharedProductId) {
    // Looked up inside the conversation's own shop. There is deliberately no
    // parameter for which shop to search: that absence is the access rule.
    const shop = business ?? (await Business.findById(conversation.business));

    if (!shop || !shop.isActive) {
      throw new AppError('Business not found', 404, 'BUSINESS_NOT_FOUND');
    }

    sharedProduct = sharedProductSnapshot(
      shop,
      findShareableProduct(shop, sharedProductId)
    );
  }

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
    body,
    sharedProduct
  });

  // What the inbox and the notification show for this thread. A card sent
  // without words would otherwise leave a blank line under the shop's name,
  // so the product's own name stands in - it is the one part of the card that
  // reads as a sentence in any language.
  const summaryBody = body || sharedProduct?.name || '';

  let updated;
  try {
    updated = await Conversation.findByIdAndUpdate(
      conversation._id,
      {
        $set: {
          lastMessage: {
            body: summaryBody,
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
        body: summaryBody
      });
    }
  } else {
    await notifyNewMessage({
      recipientId: conversation.user,
      audience: 'customer',
      businessId: conversation.business,
      conversationId: conversation._id.toString(),
      senderName,
      body: summaryBody
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
