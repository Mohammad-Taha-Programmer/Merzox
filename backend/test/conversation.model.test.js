import assert from 'node:assert/strict';
import test from 'node:test';

import mongoose from 'mongoose';

import { Conversation } from '../src/models/Conversation.js';
import { Message } from '../src/models/Message.js';

function buildConversation(overrides = {}) {
  return new Conversation({
    user: new mongoose.Types.ObjectId(),
    userName: 'ياسمين خالد',
    business: new mongoose.Types.ObjectId(),
    businessName: 'متجر الياسمين',
    businessLogoUrl: 'https://example.test/logo.png',
    ...overrides
  });
}

test('a conversation renders the counterpart for each side', () => {
  const sentAt = new Date('2026-02-18T09:43:00.000Z');
  const conversation = buildConversation({
    lastMessage: { body: 'متى المتجر بيفتح؟', senderType: 'customer', sentAt },
    unreadForUser: 0,
    unreadForBusiness: 2,
    messageCount: 5
  });

  assert.equal(conversation.validateSync(), undefined);

  const customerView = conversation.toCustomerJSON();
  const merchantView = conversation.toMerchantJSON();

  assert.equal(customerView.title, 'متجر الياسمين');
  assert.equal(customerView.avatarUrl, 'https://example.test/logo.png');
  assert.equal(customerView.unreadCount, 0);
  assert.equal(customerView.lastMessage.body, 'متى المتجر بيفتح؟');

  assert.equal(merchantView.title, 'ياسمين خالد');
  assert.equal(merchantView.unreadCount, 2);
  assert.equal(merchantView.lastMessage.senderType, 'customer');
});

test('a conversation without messages reports an empty last message', () => {
  const conversation = buildConversation();

  assert.deepEqual(conversation.toCustomerJSON().lastMessage, {
    body: '',
    senderType: 'customer',
    sentAt: null
  });
  assert.equal(conversation.toCustomerJSON().unreadCount, 0);
});

test('a message is mine only for the side that sent it', () => {
  const message = new Message({
    conversation: new mongoose.Types.ObjectId(),
    business: new mongoose.Types.ObjectId(),
    user: new mongoose.Types.ObjectId(),
    senderType: 'business',
    senderName: 'متجر الياسمين',
    body: 'هلا ، تفضلي؟'
  });

  assert.equal(message.validateSync(), undefined);
  assert.equal(message.toClientJSON('business').isMine, true);
  assert.equal(message.toClientJSON('customer').isMine, false);
  assert.equal(message.toClientJSON('customer').readAt, null);
});

test('a message body is required and capped', () => {
  const message = new Message({
    conversation: new mongoose.Types.ObjectId(),
    business: new mongoose.Types.ObjectId(),
    user: new mongoose.Types.ObjectId(),
    senderType: 'customer',
    body: 'x'.repeat(2001)
  });

  assert.notEqual(message.validateSync(), undefined);
});
